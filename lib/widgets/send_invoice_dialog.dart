import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/email_service.dart';
import '../state/active_company.dart';

/// Summary of one uninvoiced offer.
class OfferSummary {
  final String id;
  final String production;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? totalExclVat;
  bool selected;

  OfferSummary({
    required this.id,
    required this.production,
    this.startDate,
    this.endDate,
    this.totalExclVat,
    this.selected = true,
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

  // Admin email suggestions (filtered by active company)
  List<Map<String, dynamic>> _adminProfiles = [];
  List<Map<String, dynamic>> _filteredAdmins = [];

  bool get _isProduction => widget.production != null;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _nokFmt = NumberFormat('#,##0', 'nb_NO');

  @override
  void initState() {
    super.initState();

    _toCtrl = TextEditingController();
    _loadAdmins();

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

  Future<void> _loadAdmins() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return;
    try {
      // Get admin/management members of THIS company only
      final members = await _client
          .from('company_members')
          .select('user_id')
          .eq('company_id', companyId)
          .inFilter('role', ['admin', 'management']);

      final userIds = (members as List)
          .map((m) => m['user_id'] as String)
          .toList();

      if (userIds.isEmpty) return;

      final profiles = await _client
          .from('profiles')
          .select('id, name, email')
          .inFilter('id', userIds);

      if (mounted) {
        setState(() {
          _adminProfiles = List<Map<String, dynamic>>.from(profiles);
          _filteredAdmins = _adminProfiles;
        });
      }
    } catch (e) {
      debugPrint('Load admins error: $e');
    }
  }

  void _filterAdmins(String query) {
    if (query.isEmpty) {
      setState(() => _filteredAdmins = _adminProfiles);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredAdmins = _adminProfiles
          .where((p) =>
              (p['name'] as String? ?? '').toLowerCase().contains(q) ||
              (p['email'] as String? ?? '').toLowerCase().contains(q))
          .toList();
    });
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

      // 2. Confirmed OR Draft offers for those productions
      final offersRes = await _client
          .from('offers')
          .select('id, production, payload, offer_json, total_excl_vat, status')
          .inFilter('production', productionNames)
          .inFilter('status', ['Confirmed', 'Draft', 'Inquiry']);

      // 2b. Fetch prices from samletdata (same logic as Economy page)
      // samletdata has one row per DAY. Deduplicate by roundKey to get
      // one price per round, then sum rounds per offer.
      final offerIds = (offersRes as List)
          .map((o) => (o['id'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final Map<String, double> samletPrices = {};
      if (offerIds.isNotEmpty) {
        final samletRes = await _client
            .from('samletdata')
            .select('draft_id, round_id, id, pris')
            .inFilter('draft_id', offerIds)
            .not('pris', 'is', null);

        // Deduplicate exactly like Economy: roundKey = round_id ?? draft_id ?? id
        final seenRoundKeys = <String>{};
        for (final s in (samletRes as List)) {
          final draftId = (s['draft_id'] as String?)?.trim() ?? '';
          final roundId = (s['round_id'] as String?)?.trim() ?? '';
          final rowId = (s['id'] as String?)?.trim() ?? '';
          if (draftId.isEmpty) continue;

          final roundKey = roundId.isNotEmpty
              ? roundId
              : draftId.isNotEmpty
                  ? draftId
                  : rowId;

          if (seenRoundKeys.contains(roundKey)) continue;
          seenRoundKeys.add(roundKey);

          final prisStr = s['pris']?.toString() ?? '';
          if (prisStr.trim().isEmpty) continue;
          final pris = double.tryParse(
              prisStr.replaceAll(RegExp(r'[^0-9.,\-]'), '').replaceAll(',', '.'));
          if (pris != null && pris > 0) {
            samletPrices[draftId] = (samletPrices[draftId] ?? 0) + pris;
          }
        }
      }

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

      for (final o
          in (offersRes as List<dynamic>).cast<Map<String, dynamic>>()) {
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
              final d =
                  DateTime.tryParse((e as Map)['date'] as String? ?? '');
              if (d != null) {
                if (start == null || d.isBefore(start)) start = d;
                if (end == null || d.isAfter(end)) end = d;
              }
            }
          }

          // Fallback: totalOverride
          total ??= (json['totalOverride'] as num?)?.toDouble();

          // Fallback: sum of roundOverrides
          if (total == null) {
            final roundOv = json['roundOverrides'] as Map?;
            if (roundOv != null && roundOv.isNotEmpty) {
              double sum = 0;
              for (final v in roundOv.values) {
                if (v is num) sum += v.toDouble();
              }
              if (sum > 0) total = sum;
            }
          }
        }

        // Fallback: sum from samletdata (same source as Economy page)
        final offerId = o['id'] as String;
        total ??= samletPrices[offerId];

        summaries.add(OfferSummary(
          id: o['id'] as String,
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
    final list = _includeUninvoiced
        ? _uninvoiced.where((s) => s.selected).toList()
        : <OfferSummary>[];
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
      _snack("E-postadresse er påkrevd");
      return;
    }

    setState(() => _sending = true);

    try {
      await EmailService.sendEmail(
        to: to,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
        companyId: activeCompanyNotifier.value?.id,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("E-post sendt")),
      );
    } catch (e) {
      debugPrint("SEND EMAIL ERROR: $e");
      if (mounted) _snack("Kunne ikke sende: $e");
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
  String _formatDate(DateTime? d) => d != null ? _dateFmt.format(d) : '?';

  String _formatTotal(double? t) =>
      t != null ? '${_nokFmt.format(t)},-' : '–';

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isProduction
        ? 'Send fakturadetaljer – ${widget.production!['name']}'
        : 'Send fakturadetaljer – ${widget.company['name']}';

    final selectedCount =
        _uninvoiced.where((s) => s.selected).length;
    final selectedTotal = _uninvoiced
        .where((s) => s.selected && s.totalExclVat != null)
        .fold<double>(0, (sum, s) => sum + s.totalExclVat!);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 640,
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
                      Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (textEditingValue) {
                          final q = textEditingValue.text.toLowerCase();
                          if (q.isEmpty) return _adminProfiles;
                          return _adminProfiles.where((p) =>
                              (p['name'] as String? ?? '').toLowerCase().contains(q) ||
                              (p['email'] as String? ?? '').toLowerCase().contains(q));
                        },
                        displayStringForOption: (p) =>
                            p['email'] as String? ?? '',
                        onSelected: (p) {
                          _toCtrl.text = p['email'] as String? ?? '';
                        },
                        fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
                          // Sync external controller
                          ctrl.addListener(() => _toCtrl.text = ctrl.text);
                          if (_toCtrl.text.isNotEmpty && ctrl.text.isEmpty) {
                            ctrl.text = _toCtrl.text;
                          }
                          return TextField(
                            controller: ctrl,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: "Til (søk blant admins)",
                              prefixIcon: Icon(Icons.email),
                              hintText: 'Skriv navn eller e-post...',
                            ),
                          );
                        },
                        optionsViewBuilder: (ctx, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxHeight: 200, maxWidth: 520),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, i) {
                                    final p = options.elementAt(i);
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                          p['name'] as String? ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                          p['email'] as String? ?? '',
                                          style: const TextStyle(
                                              fontSize: 12)),
                                      onTap: () => onSelected(p),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        controller: _subjectCtrl,
                        decoration: const InputDecoration(
                          labelText: "Emne",
                          prefixIcon: Icon(Icons.subject),
                        ),
                      ),

                      const SizedBox(height: 12),

                      CheckboxListTile(
                        value: _includeUninvoiced,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title:
                            const Text("Inkluder ufakturerte bookinger"),
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                          )
                        else if (_uninvoiced.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 16, bottom: 8),
                            child: Text(
                              "Ingen ufakturerte bookinger med pris funnet.",
                              style:
                                  TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        else ...[
                          // Select all / none
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 8, bottom: 4),
                            child: Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      for (final s in _uninvoiced) {
                                        s.selected = true;
                                      }
                                    });
                                    _rebuildBody();
                                  },
                                  child: const Text('Velg alle',
                                      style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      for (final s in _uninvoiced) {
                                        s.selected = false;
                                      }
                                    });
                                    _rebuildBody();
                                  },
                                  child: const Text('Fjern alle',
                                      style: TextStyle(fontSize: 12)),
                                ),
                                const Spacer(),
                                Text(
                                  '$selectedCount valgt  ·  ${_nokFmt.format(selectedTotal)},-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Job list with checkboxes
                          ..._uninvoiced.map((s) => CheckboxListTile(
                                value: s.selected,
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.only(left: 8),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  s.production,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: s.selected
                                        ? null
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_formatDate(s.startDate)} – ${_formatDate(s.endDate)}  ·  ${_formatTotal(s.totalExclVat)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                onChanged: (v) {
                                  setState(
                                      () => s.selected = v ?? false);
                                  _rebuildBody();
                                },
                              )),
                          const Divider(height: 16),
                        ],
                      ],

                      const SizedBox(height: 12),

                      TextField(
                        controller: _bodyCtrl,
                        maxLines: 14,
                        decoration: InputDecoration(
                          labelText: "Melding",
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
                      child: const Text("Avbryt"),
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
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
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
