import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
// ──────────────────────────────────────────────────────────────────────────────
// MGMT GIG HIRE ADMIN PAGE
// ──────────────────────────────────────────────────────────────────────────────

class MgmtGigHireAdminPage extends StatefulWidget {
  const MgmtGigHireAdminPage({super.key});

  @override
  State<MgmtGigHireAdminPage> createState() => _MgmtGigHireAdminPageState();
}

class _MgmtGigHireAdminPageState extends State<MgmtGigHireAdminPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('dd.MM.yyyy');

  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];
  String _filter = 'outstanding'; // 'outstanding' or 'archive'

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    super.dispose();
  }

  void _onCompanyChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_companyId == null) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      // 1. Gigs for this company — only past/today (not future)
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final gigs = List<Map<String, dynamic>>.from(
        await _sb
            .from('gigs')
            .select('id, date_from, venue_name, customer_firma')
            .eq('company_id', _companyId!)
            .lte('date_from', todayStr),
      );
      if (gigs.isEmpty) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      final gigIds = gigs.map((g) => g['id'] as String).toList();
      final gigMap = {for (final g in gigs) g['id'] as String: g};

      // 2. Lineup entries for these gigs
      final lineup = List<Map<String, dynamic>>.from(
        await _sb
            .from('gig_lineup')
            .select('*')
            .inFilter('gig_id', gigIds),
      );
      if (lineup.isEmpty) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      // 3. Gig offers → fee info
      final offers = List<Map<String, dynamic>>.from(
        await _sb
            .from('gig_offers')
            .select('id, gig_id, creo_fee_minimum, extra_show_fee')
            .inFilter('gig_id', gigIds),
      );
      final offerByGig = <String, Map<String, dynamic>>{};
      for (final o in offers) {
        offerByGig[o['gig_id'] as String] = o;
      }

      // 4. Group lineup by (gig_id, user_id) to count shows & collect lineup ids
      // Key = 'gigId|userId'
      final grouped = <String, Map<String, dynamic>>{};
      for (final l in lineup) {
        final gigId = l['gig_id'] as String;
        final userId = l['user_id'] as String;
        final key = '$gigId|$userId';
        if (!grouped.containsKey(key)) {
          grouped[key] = {
            'lineup_ids': <String>[l['id'] as String],
            'gig_id': gigId,
            'user_id': userId,
            'section': l['section'] ?? '',
            'show_ids': <String>{
              if (l['show_id'] != null) l['show_id'] as String
            },
            'crew_invoiced_at': l['crew_invoiced_at'],
            'crew_paid_at': l['crew_paid_at'],
          };
        } else {
          final g = grouped[key]!;
          (g['lineup_ids'] as List<String>).add(l['id'] as String);
          if (l['show_id'] != null) {
            (g['show_ids'] as Set<String>).add(l['show_id'] as String);
          }
          // Use the earliest non-null paid/invoiced timestamps
          g['crew_invoiced_at'] ??= l['crew_invoiced_at'];
          g['crew_paid_at'] ??= l['crew_paid_at'];
        }
      }

      // 5. Profiles → names
      final userIds =
          lineup.map((l) => l['user_id'] as String).toSet().toList();
      final profiles = List<Map<String, dynamic>>.from(
        await _sb
            .from('profiles')
            .select('id, name')
            .inFilter('id', userIds),
      );
      final nameMap = {
        for (final p in profiles) p['id'] as String: p['name'] as String? ?? ''
      };

      // 6. Fetch approved expenses per gig
      final expenseRows = List<Map<String, dynamic>>.from(
        await _sb
            .from('expenses')
            .select('gig_id, user_id, amount')
            .inFilter('gig_id', gigIds)
            .eq('status', 'approved'),
      );
      // Map: gigId|userId → total expenses
      final expenseMap = <String, double>{};
      for (final e in expenseRows) {
        final key = '${e['gig_id']}|${e['user_id']}';
        expenseMap[key] = (expenseMap[key] ?? 0) +
            ((e['amount'] as num?)?.toDouble() ?? 0);
      }

      // 7. Build entries — one per person per gig
      final entries = <Map<String, dynamic>>[];
      for (final g in grouped.values) {
        final gigId = g['gig_id'] as String;
        final userId = g['user_id'] as String;
        final gig = gigMap[gigId];
        final offer = offerByGig[gigId];
        if (offer == null) continue; // skip gigs without an offer

        final creoFee =
            (offer['creo_fee_minimum'] as num?)?.toDouble() ?? 0.0;
        final extraShowFee =
            (offer?['extra_show_fee'] as num?)?.toDouble() ?? 0.0;
        final numShows = (g['show_ids'] as Set<String>).length;
        final effectiveShows = numShows > 0 ? numShows : 1;
        final hireFee = creoFee +
            (effectiveShows > 1
                ? extraShowFee * (effectiveShows - 1)
                : 0);
        final expenseTotal = expenseMap['$gigId|$userId'] ?? 0.0;
        final amount = hireFee + expenseTotal;

        entries.add({
          'lineup_ids': g['lineup_ids'],
          'lineup_id': (g['lineup_ids'] as List<String>).first,
          'gig_id': gigId,
          'user_id': g['user_id'],
          'date_from': gig?['date_from'],
          'venue_name': gig?['venue_name'] ?? '',
          'customer_firma': gig?['customer_firma'] ?? '',
          'name': nameMap[g['user_id']] ?? '',
          'section': g['section'] ?? '',
          'num_shows': effectiveShows,
          'hire_fee': hireFee,
          'expense_total': expenseTotal,
          'amount': amount,
          'crew_invoiced_at': g['crew_invoiced_at'],
          'crew_paid_at': g['crew_paid_at'],
        });
      }

      // Sort by date descending
      entries.sort((a, b) {
        final da = a['date_from'] as String? ?? '';
        final db = b['date_from'] as String? ?? '';
        return db.compareTo(da);
      });

      _entries = entries;
    } catch (e, st) {
      debugPrint('Load gig hire error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved lasting av gigghyrer: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'outstanding') {
      return _entries.where((e) => e['crew_paid_at'] == null).toList();
    }
    return _entries.where((e) => e['crew_paid_at'] != null).toList();
  }

  double get _totalOutstanding {
    return _entries
        .where((e) => e['crew_paid_at'] == null)
        .fold(0.0, (sum, e) => sum + (e['amount'] as double));
  }

  Future<void> _markInvoiced(List<String> lineupIds) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Velg fakturadato',
    );
    if (picked == null || !mounted) return;
    try {
      final iso = DateTime(picked.year, picked.month, picked.day)
          .toIso8601String();
      debugPrint('Mark invoiced: ids=$lineupIds, date=$iso');
      await _sb
          .from('gig_lineup')
          .update({'crew_invoiced_at': iso})
          .inFilter('id', lineupIds);
      await _load();
    } catch (e) {
      debugPrint('Mark invoiced error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved markering som fakturert: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearInvoiced(List<String> lineupIds) async {
    try {
      await _sb
          .from('gig_lineup')
          .update({'crew_invoiced_at': null})
          .inFilter('id', lineupIds);
      _load();
    } catch (e) {
      debugPrint('Clear invoiced error: $e');
    }
  }

  Future<void> _clearPaid(List<String> lineupIds) async {
    try {
      await _sb
          .from('gig_lineup')
          .update({'crew_paid_at': null})
          .inFilter('id', lineupIds);
      _load();
    } catch (e) {
      debugPrint('Clear paid error: $e');
    }
  }

  Future<void> _markPaid(List<String> lineupIds) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Velg betalingsdato',
    );
    if (picked == null || !mounted) return;
    try {
      final iso = DateTime(picked.year, picked.month, picked.day)
          .toIso8601String();
      debugPrint('Mark paid: ids=$lineupIds, date=$iso');
      await _sb
          .from('gig_lineup')
          .update({'crew_paid_at': iso})
          .inFilter('id', lineupIds);
      await _load();
    } catch (e) {
      debugPrint('Mark paid error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved markering som betalt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatAmount(double amount) {
    final formatted = NumberFormat('#,##0', 'nb_NO').format(amount.round());
    return '$formatted kr';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      return _df.format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final total = _totalOutstanding;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('Gigghyrer',
                  style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'outstanding', child: Text('Utestående')),
                    DropdownMenuItem(value: 'archive', child: Text('Arkiv')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _filter = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Total outstanding
          if (_filter == 'outstanding')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Totalt utestående: ${_formatAmount(total)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              _filter == 'outstanding'
                                  ? 'Ingen utestående gigghyrer'
                                  : 'Ingen betalte gigghyrer',
                              style:
                                  TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          final date = _formatDate(e['date_from'] as String?);
                          final venue = e['venue_name'] as String? ?? '';
                          final firma = e['customer_firma'] as String? ?? '';
                          final name = e['name'] as String? ?? '';
                          final section = e['section'] as String? ?? '';
                          final amount = e['amount'] as double;
                          final numShows = e['num_shows'] as int? ?? 1;
                          final invoicedAt =
                              e['crew_invoiced_at'] as String?;
                          final paidAt = e['crew_paid_at'] as String?;
                          final lineupIds =
                              List<String>.from(e['lineup_ids'] as List);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                // Date
                                SizedBox(
                                  width: 85,
                                  child: Text(date,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant)),
                                ),
                                // Venue + Firma
                                SizedBox(
                                  width: 160,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(venue,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis),
                                      if (firma.isNotEmpty)
                                        Text(firma,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs.onSurfaceVariant),
                                            overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Name
                                Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                ),
                                // Section
                                SizedBox(
                                  width: 80,
                                  child: Text(section,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant)),
                                ),
                                // Shows count
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    '$numShows show',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                // Amount (with expense breakdown)
                                SizedBox(
                                  width: 120,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatAmount(amount),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                        textAlign: TextAlign.right,
                                      ),
                                      if ((e['expense_total'] as double?) != null &&
                                          (e['expense_total'] as double) > 0)
                                        Text(
                                          'herav utlegg: ${_formatAmount(e['expense_total'] as double)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: cs.onSurfaceVariant,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Crew invoiced status + action
                                SizedBox(
                                  width: 150,
                                  child: invoicedAt != null
                                      ? Row(
                                          children: [
                                            const Icon(Icons.check_circle,
                                                size: 14,
                                                color: Colors.green),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'Fakt. ${_formatDate(invoicedAt)}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.green),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () =>
                                                  _clearInvoiced(lineupIds),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(Icons.close,
                                                    size: 14,
                                                    color: cs.onSurfaceVariant),
                                              ),
                                            ),
                                          ],
                                        )
                                      : FilledButton.icon(
                                          onPressed: () =>
                                              _markInvoiced(lineupIds),
                                          icon: const Icon(Icons.receipt,
                                              size: 14),
                                          label: const Text('Marker fakturert',
                                              style: TextStyle(fontSize: 11)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 6),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                // Paid status + action
                                if (paidAt == null)
                                  SizedBox(
                                    width: 130,
                                    child: FilledButton.icon(
                                      onPressed: () => _markPaid(lineupIds),
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Marker betalt',
                                          style: TextStyle(fontSize: 12)),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: 130,
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Betalt ${_formatDate(paidAt)}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () =>
                                              _clearPaid(lineupIds),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Icon(Icons.close,
                                                size: 14,
                                                color: cs.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
