import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/email_service.dart';

/// Summary of one uninvoiced confirmed offer.
class OfferSummary {
  final String production;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? totalExclVat;

  const OfferSummary({
    required this.production,
    this.startDate,
    this.endDate,
    this.totalExclVat,
  });
}

class SendInvoiceDialog extends StatefulWidget {
  final Map<String, dynamic> company;

  /// If set, this is a production-level send. Otherwise company-level.
  final Map<String, dynamic>? production;

  const SendInvoiceDialog({
    super.key,
    required this.company,
    this.production,
  });

  @override
  State<SendInvoiceDialog> createState() => _SendInvoiceDialogState();
}

class _SendInvoiceDialogState extends State<SendInvoiceDialog> {
  final SupabaseClient _client = Supabase.instance.client;

  late final TextEditingController _toCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  bool _includeUninvoiced = false;
  bool _loadingOffers = false;
  bool _sending = false;

  List<OfferSummary> _uninvoiced = [];

  bool get _isProduction => widget.production != null;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _nokFmt = NumberFormat('#,##0', 'nb_NO');

  @override
  void initState() {
    super.initState();

    // Pre-fill recipient from invoice_email (production → company fallback)
    final prod = widget.production;
    String prefilledEmail = '';
    if (prod != null && prod['separate_invoice_recipient'] == true) {
      prefilledEmail = prod['invoice_email'] ?? '';
    }
    if (prefilledEmail.isEmpty) {
      prefilledEmail = widget.company['invoice_email'] ?? '';
    }

    _toCtrl = TextEditingController(text: prefilledEmail);

    final built = _isProduction
        ? EmailService.buildProductionEmail(
            company: widget.company,
            production: widget.production!,
            uninvoiced: [],
          )
        : EmailService.buildCompanyEmail(
            company: widget.company,
            uninvoiced: [],
          );

    _subjectCtrl = TextEditingController(text: built.subject);
    _bodyCtrl = TextEditingController(text: built.body);
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // LOAD UNINVOICED OFFERS
  // --------------------------------------------------
  Future<void> _loadUninvoiced() async {
    setState(() => _loadingOffers = true);

    try {
      // 1. Production names to search for
      List<String> productionNames;
      if (_isProduction) {
        productionNames = [widget.production!['name'] as String];
      } else {
        final prodsRes = await _client
            .from('productions')
            .select('name')
            .eq('company_id', widget.company['id']);
        productionNames = (prodsRes as List<dynamic>)
            .map((p) => (p['name'] as String? ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (productionNames.isEmpty) {
        setState(() => _uninvoiced = []);
        _rebuildBody();
        return;
      }

      // 2. Confirmed offers for those productions
      final offersRes = await _client
          .from('offers')
          .select('id, production, payload, offer_json, total_excl_vat')
          .inFilter('production', productionNames)
          .eq('status', 'Confirmed');

      // 3. Invoiced offer IDs
      final invoicesRes = await _client
          .from('invoices')
          .select('offer_id')
          .not('offer_id', 'is', null);

      final invoicedIds = <String>{
        for (final i in invoicesRes)
          if (i['offer_id'] != null) i['offer_id'] as String,
      };

      // 4. Filter out invoiced and parse details
      final summaries = <OfferSummary>[];

      for (final o in (offersRes as List<dynamic>).cast<Map<String, dynamic>>()) {
        if (invoicedIds.contains(o['id'] as String)) continue;

        final prodName = (o['production'] as String? ?? '').trim();

        // Parse offer_json / payload for dates and price
        dynamic raw = o['payload'] ?? o['offer_json'];
        Map<String, dynamic>? json;
        try {
          json = raw is String
              ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
              : (raw as Map<String, dynamic>?);
        } catch (_) {}

        DateTime? start, end;
        double? total;

        // Price: prefer stored total_excl_vat, fall back to totalOverride in JSON
        total = (o['total_excl_vat'] as num?)?.toDouble();

        if (json != null) {
          // Date range across all rounds
          for (final r in (json['rounds'] as List? ?? [])) {
            for (final e in ((r as Map)['entries'] as List? ?? [])) {
              final d = DateTime.tryParse((e as Map)['date'] as String? ?? '');
              if (d != null) {
                if (start == null || d.isBefore(start)) start = d;
                if (end == null || d.isAfter(end)) end = d;
              }
            }
          }

          // Fallback if total_excl_vat not yet stored
          total ??= (json['totalOverride'] as num?)?.toDouble();
        }

        summaries.add(OfferSummary(
          production: prodName,
          startDate: start,
          endDate: end,
          totalExclVat: total,
        ));
      }

      // Sort by start date
      summaries.sort((a, b) {
        if (a.startDate == null && b.startDate == null) return 0;
        if (a.startDate == null) return 1;
        if (b.startDate == null) return -1;
        return a.startDate!.compareTo(b.startDate!);
      });

      setState(() => _uninvoiced = summaries);
      _rebuildBody();
    } catch (e) {
      debugPrint("LOAD UNINVOICED ERROR: $e");
    } finally {
      if (mounted) setState(() => _loadingOffers = false);
    }
  }

  void _rebuildBody() {
    final list = _includeUninvoiced ? _uninvoiced : <OfferSummary>[];
    final built = _isProduction
        ? EmailService.buildProductionEmail(
            company: widget.company,
            production: widget.production!,
            uninvoiced: list,
          )
        : EmailService.buildCompanyEmail(
            company: widget.company,
            uninvoiced: list,
          );
    _bodyCtrl.text = built.body;
  }

  // --------------------------------------------------
  // SEND
  // --------------------------------------------------
  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      _snack("Recipient email is required");
      return;
    }

    setState(() => _sending = true);

    try {
      await EmailService.sendEmail(
        to: to,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email sent")),
      );
    } catch (e) {
      debugPrint("SEND EMAIL ERROR: $e");
      if (mounted) _snack("Failed to send: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------
  // FORMAT HELPERS
  // --------------------------------------------------
  String _formatDate(DateTime? d) =>
      d != null ? _dateFmt.format(d) : '?';

  String _formatTotal(double? t) =>
      t != null ? '${_nokFmt.format(t)},-' : '–';

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isProduction
        ? 'Send invoice details – ${widget.production!['name']}'
        : 'Send invoice details – ${widget.company['name']}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 600,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 16),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _toCtrl,
                        decoration: const InputDecoration(
                          labelText: "To",
                          prefixIcon: Icon(Icons.email),
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        controller: _subjectCtrl,
                        decoration: const InputDecoration(
                          labelText: "Subject",
                          prefixIcon: Icon(Icons.subject),
                        ),
                      ),

                      const SizedBox(height: 12),

                      CheckboxListTile(
                        value: _includeUninvoiced,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Include uninvoiced confirmed bookings"),
                        onChanged: (v) async {
                          setState(() => _includeUninvoiced = v ?? false);
                          if (_includeUninvoiced && _uninvoiced.isEmpty) {
                            await _loadUninvoiced();
                          } else {
                            _rebuildBody();
                          }
                        },
                      ),

                      if (_includeUninvoiced) ...[
                        if (_loadingOffers)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        else if (_uninvoiced.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 8),
                            child: Text(
                              "No confirmed uninvoiced bookings found.",
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 8),
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(2),
                                1: FlexColumnWidth(2),
                                2: FlexColumnWidth(1),
                              },
                              children: [
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        "Production",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        "Period",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        "Excl. VAT",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                                ..._uninvoiced.map((s) => TableRow(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          child: Text(s.production),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          child: Text(
                                            '${_formatDate(s.startDate)} – ${_formatDate(s.endDate)}',
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          child: Text(
                                            _formatTotal(s.totalExclVat),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    )),
                              ],
                            ),
                          ),
                      ],

                      const SizedBox(height: 12),

                      TextField(
                        controller: _bodyCtrl,
                        maxLines: 14,
                        decoration: InputDecoration(
                          labelText: "Message",
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _sending ? null : () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text("Send"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
