import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';

class CrewGigsPage extends StatefulWidget {
  const CrewGigsPage({super.key});

  @override
  State<CrewGigsPage> createState() => _CrewGigsPageState();
}

class _CrewGigsPageState extends State<CrewGigsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _gigs = [];
  Map<String, String> _availability = {}; // gig_id -> status

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
        setState(() => _loading = false);
        return;
      }

      final gigs = await _sb
          .from('gigs')
          .select('*')
          .eq('company_id', _companyId!)
          .order('date_from', ascending: true);
      _gigs = List<Map<String, dynamic>>.from(gigs);

      // Load own availability for all gigs
      final uid = _sb.auth.currentUser?.id;
      if (uid != null) {
        final avail = await _sb
            .from('gig_availability')
            .select('gig_id, status')
            .eq('user_id', uid);
        final map = <String, String>{};
        for (final r in (avail as List)) {
          map[r['gig_id'] as String] = r['status'] as String;
        }
        _availability = map;
      }
    } catch (e) {
      debugPrint('CrewGigsPage load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter to upcoming gigs only (today onwards)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = _gigs.where((g) {
      final d = g['date_from'] as String?;
      if (d == null) return true;
      return DateTime.parse(d).isAfter(today.subtract(const Duration(days: 1)));
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gigs & Øvelser',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),

          if (upcoming.isEmpty)
            Expanded(
              child: Center(
                child: Text('Ingen kommende gigs.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: upcoming.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final gig = upcoming[i];
                  return _GigCard(
                    gig: gig,
                    availability: _availability[gig['id'] as String],
                    onTap: () =>
                        context.go('/c/gigs/${gig['id']}'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _GigCard extends StatelessWidget {
  final Map<String, dynamic> gig;
  final String? availability;
  final VoidCallback onTap;

  const _GigCard({
    required this.gig,
    this.availability,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFrom = gig['date_from'] as String?;
    final venue = gig['venue_name'] as String? ?? '';
    final city = gig['city'] as String? ?? '';
    final gigType = gig['type'] as String? ?? 'gig';
    final isRehearsal = gigType == 'rehearsal';
    final status = gig['status'] as String? ?? 'inquiry';
    final isCancelled = status == 'cancelled';

    String dateLabel = '';
    if (dateFrom != null) {
      dateLabel = DateFormat('dd.MM.yyyy').format(DateTime.parse(dateFrom));
    }

    final title = isRehearsal
        ? 'Øvelse'
        : [venue, city].where((s) => s.isNotEmpty).join(' · ');

    // Availability icon
    IconData availIcon;
    Color availColor;
    switch (availability) {
      case 'available':
        availIcon = Icons.check_circle;
        availColor = Colors.green;
        break;
      case 'unavailable':
        availIcon = Icons.cancel;
        availColor = Colors.red;
        break;
      default:
        availIcon = Icons.help_outline;
        availColor = Colors.grey;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isCancelled ? Colors.red.withValues(alpha: 0.3) : cs.outlineVariant),
        ),
        child: Row(
          children: [
            // Date column
            SizedBox(
              width: 90,
              child: Text(
                dateLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                  color: isCancelled ? cs.onSurfaceVariant : null,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Type badge (hidden when cancelled)
            if (!isCancelled)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isRehearsal
                      ? Colors.purple.withValues(alpha: 0.12)
                      : Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isRehearsal ? 'Øvelse' : 'Gig',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isRehearsal ? Colors.purple : Colors.blue,
                  ),
                ),
              ),
            if (!isCancelled) const SizedBox(width: 12),

            // Title
            Expanded(
              child: Text(
                title.isNotEmpty ? title : dateLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                  color: isCancelled ? cs.onSurfaceVariant : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Cancelled badge or availability status
            if (isCancelled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Avlyst',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red),
                ),
              )
            else
              Icon(availIcon, color: availColor, size: 22),
          ],
        ),
      ),
    );
  }
}
