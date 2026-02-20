import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/css_theme.dart';

// Status filter options
enum _StatusFilter {
  all,
  confirmedAndInvoiced,
  confirmed,
  invoiced,
  inquiry,
}

extension _StatusFilterLabel on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'All',
        _StatusFilter.confirmedAndInvoiced => 'Confirmed + Invoiced',
        _StatusFilter.confirmed => 'Confirmed only',
        _StatusFilter.invoiced => 'Invoiced only',
        _StatusFilter.inquiry => 'Inquiry only',
      };
}

class EconomyPage extends StatefulWidget {
  const EconomyPage({super.key});

  @override
  State<EconomyPage> createState() => _EconomyPageState();
}

class _EconomyPageState extends State<EconomyPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  int _selectedYear = DateTime.now().year;
  List<int> _years = [];
  _StatusFilter _filter = _StatusFilter.confirmedAndInvoiced;

  // One entry per unique round_id (deduped)
  List<_Round> _rounds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Fetch all statuses we care about
      final data = await _supabase
          .from('samletdata')
          .select('round_id, draft_id, id, dato, pris, produksjon, status')
          .or('status.eq.invoiced,status.eq.Confirmed,status.eq.confirmed,status.eq.Inquiry')
          .not('pris', 'is', null)
          .order('dato', ascending: true);

      // Two passes:
      // Pass 1 — count DAYS (all raw rows, one per date)
      // Pass 2 — deduplicate by round/draft for PRICES (one price per round)

      // days: {roundKey -> day count}
      final daysByRound = <String, int>{};
      // earliest dato per round (for month assignment)
      final firstDateByRound = <String, DateTime>{};
      // metadata per round
      final metaByRound = <String, Map<String, dynamic>>{};

      for (final r in data) {
        final roundId = (r['round_id'] as String?)?.trim() ?? '';
        final draftId = (r['draft_id'] as String?)?.trim() ?? '';
        final roundKey = roundId.isNotEmpty
            ? roundId
            : draftId.isNotEmpty
                ? draftId
                : r['id'] as String;

        final datoStr = r['dato'] as String?;
        if (datoStr == null) continue;
        DateTime dato;
        try {
          dato = DateTime.parse(datoStr);
        } catch (_) {
          continue;
        }

        daysByRound[roundKey] = (daysByRound[roundKey] ?? 0) + 1;

        // Keep earliest date for month assignment
        if (!firstDateByRound.containsKey(roundKey) ||
            dato.isBefore(firstDateByRound[roundKey]!)) {
          firstDateByRound[roundKey] = dato;
        }

        // Store metadata on first encounter
        if (!metaByRound.containsKey(roundKey)) {
          metaByRound[roundKey] = r;
        }
      }

      // Build rounds from deduplicated metadata
      final rounds = <_Round>[];
      for (final entry in metaByRound.entries) {
        final key = entry.key;
        final r = entry.value;

        final prisStr = r['pris'] as String?;
        final produksjon = (r['produksjon'] as String?)?.trim() ?? 'Unknown';
        final status = (r['status'] as String?) ?? '';

        if (prisStr == null || prisStr.trim().isEmpty) continue;
        final pris = _parsePris(prisStr);
        if (pris == null || pris <= 0) continue;

        rounds.add(_Round(
          dato: firstDateByRound[key]!,
          pris: pris,
          produksjon: produksjon,
          status: status,
          days: daysByRound[key] ?? 1,
        ));
      }

      // Sort by date ascending
      rounds.sort((a, b) => a.dato.compareTo(b.dato));

      final years = rounds.map((r) => r.dato.year).toSet().toList();
      if (!years.contains(DateTime.now().year)) years.add(DateTime.now().year);
      years.sort();

      if (!mounted) return;
      setState(() {
        _rounds = rounds;
        _years = years;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  double? _parsePris(String s) {
    final cleaned = s
        .replaceAll(' ', '')
        .replaceAll('\u00a0', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9\.]'), '');
    return double.tryParse(cleaned);
  }

  bool _statusMatch(_Round r) {
    final s = r.status.toLowerCase();
    return switch (_filter) {
      _StatusFilter.all => true,
      _StatusFilter.confirmedAndInvoiced =>
        s == 'confirmed' || s == 'invoiced',
      _StatusFilter.confirmed => s == 'confirmed',
      _StatusFilter.invoiced => s == 'invoiced',
      _StatusFilter.inquiry => s == 'inquiry',
    };
  }

  List<_Round> get _filtered => _rounds
      .where((r) => r.dato.year == _selectedYear && _statusMatch(r))
      .toList();

  List<_MonthData> get _monthlyData {
    final map = <int, _MonthData>{};
    for (final r in _filtered) {
      final m = r.dato.month;
      map[m] = _MonthData(
        month: m,
        revenue: (map[m]?.revenue ?? 0) + r.pris,
        days: (map[m]?.days ?? 0) + r.days,
      );
    }
    return map.values.toList()..sort((a, b) => a.month.compareTo(b.month));
  }

  List<_ProdData> get _productionData {
    final map = <String, _ProdData>{};
    for (final r in _filtered) {
      final p = r.produksjon;
      map[p] = _ProdData(
        production: p,
        revenue: (map[p]?.revenue ?? 0) + r.pris,
        days: (map[p]?.days ?? 0) + r.days,
      );
    }
    return map.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
  }

  double get _totalYear => _filtered.fold(0, (s, r) => s + r.pris);
  double get _avgMonth {
    final m = _monthlyData;
    return m.isEmpty ? 0 : _totalYear / m.length;
  }

  int get _totalDays => _filtered.fold(0, (s, r) => s + r.days);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Row(
                    children: [
                      Text(
                        'Economy',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 16),
                      // Year picker
                      DropdownButton<int>(
                        value: _selectedYear,
                        underline: const SizedBox(),
                        items: _years
                            .map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text('$y'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedYear = v);
                        },
                      ),
                      const SizedBox(width: 16),
                      // Status filter
                      DropdownButton<_StatusFilter>(
                        value: _filter,
                        underline: const SizedBox(),
                        items: _StatusFilter.values
                            .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.label),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _filter = v);
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _load,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Summary cards ──
                  Row(
                    children: [
                      _SummaryCard(
                        label: 'Total $_selectedYear',
                        value: _formatNok(_totalYear),
                        icon: Icons.trending_up,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _SummaryCard(
                        label: 'Avg per active month',
                        value: _formatNok(_avgMonth),
                        icon: Icons.calendar_month,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _SummaryCard(
                        label: 'Days with buses out',
                        value: '$_totalDays',
                        icon: Icons.directions_bus_outlined,
                        color: Colors.orange,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Monthly + Productions ──
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _Section(
                            title: 'Monthly Breakdown',
                            child: _monthlyData.isEmpty
                                ? const Center(
                                    child: Text('No data',
                                        style: TextStyle(
                                            color: CssTheme.textMuted)))
                                : _MonthlyTable(months: _monthlyData),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _Section(
                            title: 'Per Production',
                            child: _productionData.isEmpty
                                ? const Center(
                                    child: Text('No data',
                                        style: TextStyle(
                                            color: CssTheme.textMuted)))
                                : _ProductionTable(
                                    productions: _productionData,
                                    totalYear: _totalYear,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MONTHLY TABLE WITH BAR
// ─────────────────────────────────────────────────────────
class _MonthlyTable extends StatelessWidget {
  final List<_MonthData> months;
  const _MonthlyTable({required this.months});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxRev = months.fold(0.0, (m, r) => r.revenue > m ? r.revenue : m);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _h('Month', flex: 2),
            _h('Days', flex: 1),
            _h('Revenue', flex: 3),
            _h('', flex: 4),
          ]),
        ),
        ...months.map((m) {
          final frac = maxRev > 0 ? m.revenue / maxRev : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    DateFormat('MMMM').format(DateTime(2000, m.month)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text('${m.days}',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55))),
                ),
                Expanded(
                  flex: 3,
                  child: Text(_formatNok(m.revenue),
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 4,
                  child: LayoutBuilder(
                    builder: (_, box) => Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: frac.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _h(String t, {int flex = 1}) => Expanded(
        flex: flex,
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: CssTheme.textMuted)),
      );
}

// ─────────────────────────────────────────────────────────
// PRODUCTION TABLE
// ─────────────────────────────────────────────────────────
class _ProductionTable extends StatelessWidget {
  final List<_ProdData> productions;
  final double totalYear;
  const _ProductionTable(
      {required this.productions, required this.totalYear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _h('Production', flex: 4),
            _h('Days', flex: 1),
            _h('Revenue', flex: 3),
            _h('%', flex: 1),
          ]),
        ),
        ...productions.map((p) {
          final pct =
              totalYear > 0 ? (p.revenue / totalYear * 100) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(p.production,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 1,
                  child: Text('${p.days}',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55))),
                ),
                Expanded(
                  flex: 3,
                  child: Text(_formatNok(p.revenue),
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 12)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _h(String t, {int flex = 1}) => Expanded(
        flex: flex,
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: CssTheme.textMuted)),
      );
}

// ─────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: CssTheme.textMuted,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.3)),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────
class _Round {
  final DateTime dato;
  final double pris;
  final String produksjon;
  final String status;
  final int days;
  const _Round(
      {required this.dato,
      required this.pris,
      required this.produksjon,
      required this.status,
      required this.days});
}

class _MonthData {
  final int month;
  final double revenue;
  final int days;
  const _MonthData(
      {required this.month, required this.revenue, required this.days});
}

class _ProdData {
  final String production;
  final double revenue;
  final int days;
  const _ProdData(
      {required this.production,
      required this.revenue,
      required this.days});
}

String _formatNok(double v) =>
    'kr ${NumberFormat('#,###', 'nb_NO').format(v.round())}';
