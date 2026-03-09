import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
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
  bool _showArchivedBusRequests = false;

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
          .select('show_tours, show_bus_requests_mgmt')
          .eq('id', _companyId!)
          .maybeSingle();
      _showTours = company?['show_tours'] != false;
      _showBusRequests = company?['show_bus_requests_mgmt'] != false;

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
          .select('id, date_from, date_to, venue_name, city, status, type, customer_firma, customer_name, cancellation_reason')
          .eq('company_id', _companyId!)
          .gte('date_from', fmt.format(now))
          .lte('date_from', fmt.format(in30))
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
        final baseQuery = _sb
            .from('bus_requests')
            .select('*, management_tours(name, artist)')
            .eq('company_id', _companyId!);
        final pending = _showArchivedBusRequests
            ? await baseQuery
                .eq('archived_mgmt', true)
                .order('created_at', ascending: false)
            : await baseQuery
                .eq('archived_mgmt', false)
                .inFilter('status', ['pending', 'offer_sent', 'accepted_by_client', 'accepted', 'confirmed', 'declined', 'cancelled'])
                .order('created_at', ascending: false);
        final rows = List<Map<String, dynamic>>.from(pending);

        // Look up pdf_path from offers table for rows that have an offer
        for (final r in rows) {
          final offerId = r['offer_id'] as String?;
          if (offerId != null) {
            try {
              final offer = await _sb
                  .from('offers')
                  .select('pdf_path')
                  .eq('id', offerId)
                  .maybeSingle();
              r['_pdf_path'] = offer?['pdf_path'] as String?;
            } catch (_) {}
          }
        }
        _pendingBusRequests = rows;
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
    final cs = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'God morgen'
        : hour < 18
            ? 'God ettermiddag'
            : 'God kveld';

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
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Upcoming events (tour shows + gigs)
                  _SectionHeader(
                    title: 'Kommende hendelser',
                    subtitle: 'Neste 30 dager',
                    count: _upcomingEvents.length,
                    action: TextButton(
                      onPressed: () => context.go('/m/gigs'),
                      child: const Text('Se gigs'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_upcomingEvents.isEmpty)
                    _EmptyCard(message: 'Ingen kommende hendelser de neste 30 dagene')
                  else
                    ..._upcomingEvents.map((event) => _EventCard(event: event)),

                  if (_showTours) ...[
                    const SizedBox(height: 24),

                    // Active tours
                    _SectionHeader(
                      title: 'Aktive turnéer',
                      count: _activeTours.length,
                      action: TextButton(
                        onPressed: () => context.go('/m/tours'),
                        child: const Text('Se alle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_activeTours.isEmpty)
                      _EmptyCard(message: 'Ingen aktive turnéer')
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

                    // Bus requests
                    _SectionHeader(
                      title: _showArchivedBusRequests
                          ? 'Arkiverte bussforespørsler'
                          : 'Bussforespørsler',
                      count: _pendingBusRequests.length,
                      action: IconButton(
                        icon: Icon(
                          _showArchivedBusRequests
                              ? Icons.inbox
                              : Icons.archive_outlined,
                          size: 20,
                        ),
                        tooltip: _showArchivedBusRequests
                            ? 'Vis aktive'
                            : 'Vis arkiverte',
                        onPressed: () {
                          setState(() => _showArchivedBusRequests =
                              !_showArchivedBusRequests);
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_pendingBusRequests.isEmpty)
                      _EmptyCard(
                        message: _showArchivedBusRequests
                            ? 'Ingen arkiverte bussforespørsler'
                            : 'Ingen bussforespørsler',
                      )
                    else
                      ..._pendingBusRequests.map((r) => _BusRequestCard(
                            request: r,
                            onReload: _load,
                            isArchiveView: _showArchivedBusRequests,
                          )),
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
    final cs = Theme.of(context).colorScheme;
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
                  color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
    final isCancelled = status == 'cancelled';
    final cancellationReason = event['cancellation_reason'] as String?;

    return GestureDetector(
      onTap: isGig ? () => context.go('/m/gigs/${event['id']}') : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isCancelled ? Colors.red.withValues(alpha: 0.3) : cs.outlineVariant),
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
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    dateStr != null
                        ? DateFormat('d').format(DateTime.parse(dateStr))
                        : '',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                      color: isCancelled ? cs.onSurfaceVariant : null,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                      color: isCancelled ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  if (isCancelled && cancellationReason != null && cancellationReason.isNotEmpty)
                    Text(
                      cancellationReason,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            // Cancelled badge (replaces type/status badges)
            if (isCancelled) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Text('Avlyst',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red)),
              ),
            ] else if (gigType == 'rehearsal') ...[
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
            if (!isCancelled && gigType != 'rehearsal')
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
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
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
              style: TextStyle(color: cs.onSurfaceVariant),
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
  final VoidCallback onReload;
  final bool isArchiveView;
  const _BusRequestCard({
    required this.request,
    required this.onReload,
    this.isArchiveView = false,
  });

  Future<void> _approve(BuildContext context) async {
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .update({'status': 'accepted_by_client'}).eq('id', id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Godkjenning sendt')),
      );
    }
    onReload();
  }

  Future<void> _decline(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avslå tilbud?'),
        content: const Text('Er du sikker på at du vil avslå dette tilbudet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Avslå'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .update({'status': 'declined'}).eq('id', id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tilbud avslått')),
      );
    }
    onReload();
  }

  Future<void> _cancel(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avlys bussforespørsel?'),
        content: const Text('Er du sikker på at du vil avlyse denne forespørselen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Avlys'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .update({'status': 'cancelled'}).eq('id', id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forespørsel avlyst')),
      );
    }
    onReload();
  }

  Future<void> _archive(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arkiver forespørsel?'),
        content: const Text('Forespørselen flyttes til arkivet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arkiver'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .update({'archived_mgmt': true}).eq('id', id);
    onReload();
  }

  Future<void> _restore(BuildContext context) async {
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .update({'archived_mgmt': false}).eq('id', id);
    onReload();
  }

  Future<void> _permanentlyDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett permanent?'),
        content: const Text(
            'Denne forespørselen slettes permanent. Handlingen kan ikke angres.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett permanent'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = request['id'] as String;
    await Supabase.instance.client
        .from('bus_requests')
        .delete()
        .eq('id', id);
    onReload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from = request['date_from'] as String? ?? '';
    final to = request['date_to'] as String? ?? '';
    final fromCity = request['from_city'] as String? ?? '';
    final toCity = request['to_city'] as String? ?? '';
    final pax = request['pax'] as int?;
    final status = request['status'] as String? ?? 'pending';
    final tour = request['management_tours'] as Map<String, dynamic>?;
    final tourName = tour?['name'] as String? ?? '';

    final pdfPath = request['_pdf_path'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
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
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                if (tourName.isNotEmpty)
                  Text(
                    tourName,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (pdfPath != null) ...[
            TextButton.icon(
              onPressed: () {
                final url = Supabase.instance.client.storage
                    .from('offer-pdfs')
                    .getPublicUrl(pdfPath);
                showDialog<void>(
                  context: context,
                  builder: (_) => _PdfViewDialog(pdfUrl: url),
                );
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Se tilbud'),
            ),
            const SizedBox(width: 8),
          ],
          if (status == 'offer_sent') ...[
            FilledButton.icon(
              onPressed: () => _approve(context),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Godkjenn'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _decline(context),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Avslå'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (status == 'accepted_by_client') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Venter på bekreftelse',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Cancel button for active statuses (pending, offer_sent, accepted_by_client, confirmed)
          if (!isArchiveView &&
              ['pending', 'offer_sent', 'accepted_by_client', 'confirmed'].contains(status)) ...[
            OutlinedButton.icon(
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Avlys'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Archive button for terminal statuses (active view)
          if (!isArchiveView &&
              ['accepted', 'confirmed', 'declined', 'cancelled'].contains(status)) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _archive(context),
              icon: const Icon(Icons.archive_outlined, size: 18),
              tooltip: 'Arkiver',
              style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          ],
          // Restore + Delete buttons (archive view)
          if (isArchiveView) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _restore(context),
              icon: const Icon(Icons.unarchive_outlined, size: 16),
              label: const Text('Gjenopprett'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _permanentlyDelete(context),
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Slett permanent'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
          if (!isArchiveView) ...[
            const SizedBox(width: 8),
          ],
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
      'offer_sent': Colors.teal,
      'accepted_by_client': Colors.amber,
      'accepted': Colors.green,
      'declined': Colors.red,
      'rejected': Colors.red,
    };
    final labels = {
      'planning': 'Planlegger',
      'active': 'Aktiv',
      'completed': 'Fullført',
      'cancelled': 'Avlyst',
      'confirmed': 'Bekreftet',
      'hold': 'På vent',
      'pending': 'Venter',
      'quoted': 'Tilbudt',
      'offer_sent': 'Tilbud sendt',
      'accepted_by_client': 'Godkjent',
      'accepted': 'Akseptert',
      'declined': 'Avslått',
      'rejected': 'Avvist',
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
        labels[status] ?? status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================
// PDF VIEW DIALOG
// ============================================================

class _PdfViewDialog extends StatefulWidget {
  final String pdfUrl;
  const _PdfViewDialog({required this.pdfUrl});

  @override
  State<_PdfViewDialog> createState() => _PdfViewDialogState();
}

class _PdfViewDialogState extends State<_PdfViewDialog> {
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final res = await http.get(Uri.parse(widget.pdfUrl));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      setState(() {
        _pdfBytes = res.bodyBytes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      child: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.picture_as_pdf, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tilbud',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 48),
                              const SizedBox(height: 12),
                              Text('Kunne ikke laste PDF: $_error'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _loading = true;
                                    _error = null;
                                    _pdfBytes = null;
                                  });
                                  _loadPdf();
                                },
                                child: const Text('Prøv igjen'),
                              ),
                            ],
                          ),
                        )
                      : PdfPreview(
                          build: (_) async => _pdfBytes!,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          allowPrinting: true,
                          allowSharing: true,
                          maxPageWidth: 800,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
