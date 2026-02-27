import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
import '../../ui/css_theme.dart';

class MgmtDashboardPage extends StatefulWidget {
  const MgmtDashboardPage({super.key});

  @override
  State<MgmtDashboardPage> createState() => _MgmtDashboardPageState();
}

class _MgmtDashboardPageState extends State<MgmtDashboardPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _userName;
  String? get _companyId => activeCompanyNotifier.value?.id;
  bool _showTours = true;
  bool _showBusRequests = true;

  // Combined upcoming events: management_shows (tour-based) + gigs
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _activeTours = [];
  List<Map<String, dynamic>> _pendingBusRequests = [];

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
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      // Load user name from profile (company comes from notifier)
      final profile = await _sb
          .from('profiles')
          .select('name')
          .eq('id', uid)
          .maybeSingle();
      _userName = profile?['name'] as String?;

      if (_companyId == null) {
        setState(() => _loading = false);
        return;
      }

      // Load feature flags
      final company = await _sb
          .from('companies')
          .select('show_tours, show_bus_requests')
          .eq('id', _companyId!)
          .maybeSingle();
      _showTours = company?['show_tours'] != false;
      _showBusRequests = company?['show_bus_requests'] != false;

      final now = DateTime.now();
      final in30 = now.add(const Duration(days: 30));
      final fmt = DateFormat('yyyy-MM-dd');

      // Upcoming tour shows (management_shows) in next 30 days
      final List<Map<String, dynamic>> tourShows = [];
      if (_showTours) {
        final tourIds = await _sb
            .from('management_tours')
            .select('id')
            .eq('company_id', _companyId!);
        final ids = (tourIds as List).map((t) => t['id'] as String).toList();

        if (ids.isNotEmpty) {
          final shows = await _sb
              .from('management_shows')
              .select('*, management_tours!inner(name, artist)')
              .inFilter('tour_id', ids)
              .gte('date', fmt.format(now))
              .lte('date', fmt.format(in30))
              .neq('status', 'cancelled')
              .order('date');
          for (final s in (shows as List)) {
            final m = Map<String, dynamic>.from(s as Map);
            m['_source'] = 'tour_show';
            m['_sortDate'] = m['date'] as String? ?? '';
            tourShows.add(m);
          }
        }
      }

      // Upcoming gigs in next 30 days
      final gigsRaw = await _sb
          .from('gigs')
          .select('id, date_from, date_to, venue_name, city, status, type, customer_firma, customer_name')
          .eq('company_id', _companyId!)
          .gte('date_from', fmt.format(now))
          .lte('date_from', fmt.format(in30))
          .neq('status', 'cancelled')
          .order('date_from');
      final List<Map<String, dynamic>> gigEvents = [];
      for (final g in (gigsRaw as List)) {
        final m = Map<String, dynamic>.from(g as Map);
        m['_source'] = 'gig';
        m['_sortDate'] = m['date_from'] as String? ?? '';
        gigEvents.add(m);
      }

      // Merge and sort by date
      final all = [...tourShows, ...gigEvents];
      all.sort((a, b) => (a['_sortDate'] as String).compareTo(b['_sortDate'] as String));
      _upcomingEvents = all;

      // Active tours
      if (_showTours) {
        final activeTours = await _sb
            .from('management_tours')
            .select('*')
            .eq('company_id', _companyId!)
            .eq('status', 'active')
            .order('tour_start');
        _activeTours = List<Map<String, dynamic>>.from(activeTours);
      } else {
        _activeTours = [];
      }

      // Pending bus requests
      if (_showBusRequests) {
        final pending = await _sb
            .from('bus_requests')
            .select('*, management_tours(name, artist)')
            .eq('company_id', _companyId!)
            .eq('status', 'pending')
            .order('created_at', ascending: false);
        _pendingBusRequests = List<Map<String, dynamic>>.from(pending);
      } else {
        _pendingBusRequests = [];
      }

    } catch (e) {
      debugPrint('Dashboard load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.all(18),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting${_userName != null ? ', $_userName' : ''}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CssTheme.textMuted,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Upcoming events (tour shows + gigs)
                  _SectionHeader(
                    title: 'Upcoming Events',
                    subtitle: 'Next 30 days',
                    count: _upcomingEvents.length,
                    action: TextButton(
                      onPressed: () => context.go('/m/gigs'),
                      child: const Text('View gigs'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_upcomingEvents.isEmpty)
                    _EmptyCard(message: 'No upcoming events in the next 30 days')
                  else
                    ..._upcomingEvents.map((event) => _EventCard(event: event)),

                  if (_showTours) ...[
                    const SizedBox(height: 24),

                    // Active tours
                    _SectionHeader(
                      title: 'Active Tours',
                      count: _activeTours.length,
                      action: TextButton(
                        onPressed: () => context.go('/m/tours'),
                        child: const Text('View all'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_activeTours.isEmpty)
                      _EmptyCard(message: 'No active tours')
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _activeTours
                            .map((t) => _TourCard(
                                  tour: t,
                                  onTap: () =>
                                      context.go('/m/tours/${t['id']}'),
                                ))
                            .toList(),
                      ),
                  ],

                  if (_showBusRequests) ...[
                    const SizedBox(height: 24),

                    // Pending bus requests
                    _SectionHeader(
                      title: 'Pending Bus Requests',
                      count: _pendingBusRequests.length,
                    ),
                    const SizedBox(height: 12),
                    if (_pendingBusRequests.isEmpty)
                      _EmptyCard(message: 'No pending bus requests')
                    else
                      ..._pendingBusRequests
                          .map((r) => _BusRequestCard(request: r)),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int count;
  final Widget? action;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.count = 0,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: CssTheme.primary2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CssTheme.textMuted,
                ),
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CssTheme.outline),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CssTheme.textMuted,
            ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final source = event['_source'] as String? ?? 'tour_show';
    final isGig = source == 'gig';

    // Date: tour shows use 'date', gigs use 'date_from'
    final dateStr = isGig
        ? event['date_from'] as String?
        : event['date'] as String?;

    final venue = event['venue_name'] as String? ?? '';
    final city = event['city'] as String? ?? '';
    final status = event['status'] as String? ?? 'confirmed';

    // Label line 1 (bold title)
    String title;
    String subtitle;
    if (isGig) {
      final type = event['type'] as String? ?? 'gig';
      final firma = event['customer_firma'] as String? ?? '';
      final custName = event['customer_name'] as String? ?? '';
      if (type == 'rehearsal') {
        title = 'Øvelse';
        subtitle = [venue, city].where((s) => s.isNotEmpty).join(' · ');
      } else {
        title = [if (venue.isNotEmpty) venue, if (city.isNotEmpty) city].join(', ');
        if (title.isEmpty) title = 'Gig';
        subtitle = [firma, custName].where((s) => s.isNotEmpty).join(' — ');
      }
    } else {
      final tour = event['management_tours'] as Map<String, dynamic>?;
      final tourName = tour?['name'] as String? ?? '';
      final artist = tour?['artist'] as String? ?? '';
      title = artist.isNotEmpty ? artist : tourName;
      subtitle = [if (venue.isNotEmpty) venue, if (city.isNotEmpty) city].join(', ');
    }

    // Type badge
    final gigType = isGig ? (event['type'] as String? ?? 'gig') : null;

    return GestureDetector(
      onTap: isGig ? () => context.go('/m/gigs/${event['id']}') : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CssTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CssTheme.outline),
        ),
        child: Row(
          children: [
            // Date block
            Container(
              width: 56,
              alignment: Alignment.center,
              child: Column(
                children: [
                  Text(
                    dateStr != null
                        ? DateFormat('MMM').format(DateTime.parse(dateStr))
                        : '',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: CssTheme.textMuted,
                    ),
                  ),
                  Text(
                    dateStr != null
                        ? DateFormat('d').format(DateTime.parse(dateStr))
                        : '',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(color: CssTheme.textMuted),
                    ),
                ],
              ),
            ),
            // Type badge for gigs
            if (gigType == 'rehearsal') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: const Text('Øvelse',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.purple)),
              ),
              const SizedBox(width: 8),
            ] else if (isGig) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                ),
                child: const Text('Gig',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.blue)),
              ),
              const SizedBox(width: 8),
            ],
            if (gigType != 'rehearsal')
              _StatusBadge(status: status),
          ],
        ),
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final Map<String, dynamic> tour;
  final VoidCallback onTap;

  const _TourCard({required this.tour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CssTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CssTheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tour['name'] as String? ?? '',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              tour['artist'] as String? ?? '',
              style: const TextStyle(color: CssTheme.textMuted),
            ),
            const SizedBox(height: 8),
            _StatusBadge(status: tour['status'] as String? ?? 'planning'),
          ],
        ),
      ),
    );
  }
}

class _BusRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  const _BusRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final from = request['date_from'] as String? ?? '';
    final to = request['date_to'] as String? ?? '';
    final fromCity = request['from_city'] as String? ?? '';
    final toCity = request['to_city'] as String? ?? '';
    final pax = request['pax'] as int?;
    final status = request['status'] as String? ?? 'pending';
    final tour = request['management_tours'] as Map<String, dynamic>?;
    final tourName = tour?['name'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CssTheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$fromCity → $toCity',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '$from → $to${pax != null ? '  •  $pax pax' : ''}',
                  style: const TextStyle(color: CssTheme.textMuted),
                ),
                if (tourName.isNotEmpty)
                  Text(
                    tourName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CssTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          _StatusBadge(status: status),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'planning': Colors.blue,
      'active': Colors.green,
      'completed': Colors.grey,
      'cancelled': Colors.red,
      'confirmed': Colors.green,
      'hold': Colors.orange,
      'pending': Colors.orange,
      'quoted': Colors.blue,
      'accepted': Colors.green,
      'rejected': Colors.red,
    };

    final color = colors[status] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
