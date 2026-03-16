import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/css_theme.dart';
import '../services/bus_availability_service.dart';

// Global notifier for CSS sidebar badge count
final busRequestsBadgeNotifier = ValueNotifier<int>(0);

class BusRequestsPage extends StatefulWidget {
  const BusRequestsPage({super.key});

  @override
  State<BusRequestsPage> createState() => _BusRequestsPageState();
}

class _BusRequestsPageState extends State<BusRequestsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  String _filterStatus = 'all';
  int _pendingCount = 0;
  int _awaitingConfirmCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final query = _sb
          .from('bus_requests')
          .select('*, companies(name), management_tours(name, artist), gigs(venue_name, city, date_from, date_to, customer_firma, customer_name, customer_phone, customer_email), bus_request_gigs(sort_order, round_index, round_start_city, round_end_city, gigs(id, venue_name, city, date_from, date_to, customer_name, customer_phone, customer_email))');

      final List<dynamic> data;
      if (_filterStatus == 'archived') {
        data = await query
            .eq('archived_css', true)
            .order('created_at', ascending: false);
      } else if (_filterStatus == 'all') {
        data = await query
            .eq('archived_css', false)
            .order('created_at', ascending: false);
      } else {
        data = await query
            .eq('status', _filterStatus)
            .eq('archived_css', false)
            .order('created_at', ascending: false);
      }

      _requests = List<Map<String, dynamic>>.from(data);

      // Update badge counts (exclude archived)
      final pendingRows = await _sb
          .from('bus_requests')
          .select('id')
          .eq('status', 'pending')
          .eq('archived_css', false);
      _pendingCount = (pendingRows as List).length;

      final awaitingRows = await _sb
          .from('bus_requests')
          .select('id')
          .eq('status', 'accepted_by_client')
          .eq('archived_css', false);
      _awaitingConfirmCount = (awaitingRows as List).length;

      final cancelledRows = await _sb
          .from('bus_requests')
          .select('id')
          .eq('status', 'cancelled')
          .eq('archived_css', false);
      final cancelledCount = (cancelledRows as List).length;

      busRequestsBadgeNotifier.value = _pendingCount + _awaitingConfirmCount + cancelledCount;
    } catch (e) {
      debugPrint('BusRequests load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reject(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request?'),
        content: const Text('This will mark the request as rejected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _sb
          .from('bus_requests')
          .update({'status': 'rejected'}).eq('id', requestId);
      await _load();
    }
  }

  Future<void> _createOffer(Map<String, dynamic> request) async {
    final dateFrom = request['date_from'] as String? ?? '';
    final dateTo = request['date_to'] as String? ?? '';
    final fromCity = request['from_city'] as String? ?? '';
    final toCity = request['to_city'] as String? ?? '';
    final company = request['companies'] as Map<String, dynamic>?;
    final companyName = company?['name'] as String? ?? '';
    final busRequestId = request['id'] as String;
    final pax = request['pax'] as int?;
    final busCount = request['bus_count'] as int?;
    final trailer = request['trailer'] as bool? ?? false;

    // Build stops list for the route (from junction gigs sorted by sort_order)
    final junctionGigs = (request['bus_request_gigs'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

    // Group gigs by round_index for multi-round support
    final Map<int, List<Map<String, dynamic>>> roundGroups = {};
    for (final jg in junctionGigs) {
      final ri = jg['round_index'] as int? ?? 0;
      roundGroups.putIfAbsent(ri, () => []);
      roundGroups[ri]!.add(jg);
    }

    // Build rounds param: "startCity|endCity|date:city,date:city;startCity|endCity|date:city,date:city"
    String? roundsData;
    if (roundGroups.length > 1 || roundGroups.values.any((g) => g.first['round_start_city'] != null)) {
      final sortedKeys = roundGroups.keys.toList()..sort();
      final roundStrings = <String>[];
      for (final ri in sortedKeys) {
        final gigs = roundGroups[ri]!;
        final startCity = gigs.first['round_start_city'] as String? ?? fromCity;
        final endCity = gigs.first['round_end_city'] as String? ?? toCity;
        final gigParts = gigs.map((jg) {
          final g = jg['gigs'] as Map<String, dynamic>?;
          final city = g?['city'] as String? ?? '';
          final date = g?['date_from'] as String? ?? '';
          return '$date:$city';
        }).where((s) => s.length > 1).join(',');
        roundStrings.add('$startCity|$endCity|$gigParts');
      }
      roundsData = roundStrings.join(';');
    }

    // Fallback: flat stops for single-round (backwards compat)
    final stops = junctionGigs
        .map((jg) => jg['gigs'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((g) => g['city'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .join(',');

    // Build production name
    final tour = request['management_tours'] as Map<String, dynamic>?;
    final production = tour?['name'] as String? ?? '';

    if (mounted) {
      final params = <String, String>{
        'busRequestId': busRequestId,
        if (companyName.isNotEmpty) 'company': companyName,
        if (production.isNotEmpty) 'production': production,
        if (fromCity.isNotEmpty) 'fromCity': fromCity,
        if (toCity.isNotEmpty) 'toCity': toCity,
        if (dateFrom.isNotEmpty) 'dateFrom': dateFrom,
        if (dateTo.isNotEmpty) 'dateTo': dateTo,
        if (stops.isNotEmpty) 'stops': stops,
        if (roundsData != null) 'rounds': roundsData,
        if (pax != null) 'pax': pax.toString(),
        if (busCount != null) 'busCount': busCount.toString(),
        if (trailer) 'trailer': 'true',
      };
      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      context.go('/new?$queryString');
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    await _sb
        .from('bus_requests')
        .update({'status': 'confirmed'}).eq('id', requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forespørsel bekreftet')),
      );
    }
    await _load();
  }

  Future<void> _declineRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avslå forespørsel?'),
        content: const Text('Er du sikker på at du vil avslå denne forespørselen?'),
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
    if (confirm == true) {
      await _sb
          .from('bus_requests')
          .update({'status': 'declined'}).eq('id', requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forespørsel avslått')),
        );
      }
      await _load();
    }
  }

  Future<void> _archiveRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive request?'),
        content: const Text('This request will be moved to your archive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _sb
          .from('bus_requests')
          .update({'archived_css': true}).eq('id', requestId);
      await _load();
    }
  }

  Future<void> _restoreRequest(String requestId) async {
    await _sb
        .from('bus_requests')
        .update({'archived_css': false}).eq('id', requestId);
    await _load();
  }

  Future<void> _permanentlyDeleteRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
            'This request will be permanently deleted. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _sb.from('bus_requests').delete().eq('id', requestId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bus Requests',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    'Incoming requests from management companies',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CssTheme.textMuted,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              // Status filter
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'pending',
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Pending'),
                        if (_pendingCount > 0) ...[
                          const SizedBox(width: 6),
                          _BadgeChip(count: _pendingCount),
                        ],
                      ],
                    ),
                  ),
                  const ButtonSegment(value: 'quoted', label: Text('Quoted')),
                  ButtonSegment(
                    value: 'accepted_by_client',
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Awaiting confirm'),
                        if (_awaitingConfirmCount > 0) ...[
                          const SizedBox(width: 6),
                          _BadgeChip(count: _awaitingConfirmCount),
                        ],
                      ],
                    ),
                  ),
                  const ButtonSegment(value: 'all', label: Text('All')),
                  const ButtonSegment(value: 'archived', label: Text('Archived')),
                ],
                selected: {_filterStatus},
                onSelectionChanged: (s) {
                  setState(() => _filterStatus = s.first);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_bus_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filterStatus == 'pending'
                                  ? 'No pending requests'
                                  : _filterStatus == 'archived'
                                      ? 'No archived requests'
                                      : 'No requests',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: CssTheme.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _requests.length,
                        itemBuilder: (context, i) {
                          final req = _requests[i];
                          return _BusRequestCard(
                            request: req,
                            onCreateOffer: () => _createOffer(req),
                            onReject: () => _reject(req['id']),
                            onAccept: () => _acceptRequest(req['id']),
                            onDecline: () => _declineRequest(req['id']),
                            onArchive: () => _archiveRequest(req['id']),
                            onRestore: () => _restoreRequest(req['id']),
                            onDelete: () => _permanentlyDeleteRequest(req['id']),
                            isArchiveView: _filterStatus == 'archived',
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _BusRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCreateOffer;
  final VoidCallback onReject;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final bool isArchiveView;

  const _BusRequestCard({
    required this.request,
    required this.onCreateOffer,
    required this.onReject,
    this.onAccept,
    this.onDecline,
    this.onArchive,
    this.onRestore,
    this.onDelete,
    this.isArchiveView = false,
  });

  @override
  State<_BusRequestCard> createState() => _BusRequestCardState();
}

class _BusRequestCardState extends State<_BusRequestCard> {
  Map<String, bool>? _availability;
  bool _loadingAvailability = true;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final dateFrom = widget.request['date_from'] as String?;
    final dateTo = widget.request['date_to'] as String?;
    if (dateFrom == null || dateTo == null) {
      setState(() => _loadingAvailability = false);
      return;
    }
    try {
      final avail = await BusAvailabilityService.fetchAvailability(
        start: DateTime.parse(dateFrom),
        end: DateTime.parse(dateTo),
      );
      if (mounted) setState(() {
        _availability = avail;
        _loadingAvailability = false;
      });
    } catch (e) {
      debugPrint('Availability check error: $e');
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final company = req['companies'] as Map<String, dynamic>?;
    final companyName = company?['name'] as String? ?? 'Unknown company';
    final tour = req['management_tours'] as Map<String, dynamic>?;
    final tourName = tour?['name'] as String? ?? '';
    final artist = tour?['artist'] as String? ?? '';
    final gig = req['gigs'] as Map<String, dynamic>?;
    final dateFrom = req['date_from'] as String? ?? '';
    final dateTo = req['date_to'] as String? ?? '';
    final fromCity = req['from_city'] as String? ?? '';
    final toCity = req['to_city'] as String? ?? '';
    final pax = req['pax'] as int?;
    final trailer = req['trailer'] as bool? ?? false;
    final busCount = req['bus_count'] as int?;
    final notes = req['notes'] as String? ?? '';
    final status = req['status'] as String? ?? 'pending';
    final createdAt = req['created_at'] as String?;

    final isPending = status == 'pending';
    final isAwaitingConfirm = status == 'accepted_by_client';

    // Multi-gig route from junction table
    final junctionGigs = (req['bus_request_gigs'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

    final gigStops = junctionGigs
        .map((jg) {
          final g = jg['gigs'] as Map<String, dynamic>?;
          return g?['city'] as String? ?? '';
        })
        .where((c) => c.isNotEmpty)
        .toList();

    // Build full route string: fromCity → stop1 → stop2 → toCity
    final routeParts = <String>[
      if (fromCity.isNotEmpty) fromCity,
      ...gigStops,
      if (toCity.isNotEmpty) toCity,
    ];
    final routeLabel = routeParts.isNotEmpty
        ? routeParts.join(' → ')
        : '$fromCity → $toCity';

    // Subtitle — gig details or tour info
    String subtitle = '';
    if (junctionGigs.isNotEmpty) {
      subtitle = junctionGigs.map((jg) {
        final g = jg['gigs'] as Map<String, dynamic>?;
        if (g == null) return '';
        final venue = g['venue_name'] as String? ?? '';
        final city = g['city'] as String? ?? '';
        final d = g['date_from'] as String?;
        final dateStr = d != null ? DateFormat('dd.MM').format(DateTime.parse(d)) : '';
        return '$dateStr ${[venue, city].where((s) => s.isNotEmpty).join(' · ')}'.trim();
      }).where((s) => s.isNotEmpty).join('  |  ');
    } else if (gig != null) {
      final gigVenue = gig['venue_name'] as String? ?? '';
      final gigCity = gig['city'] as String? ?? '';
      subtitle = [gigVenue, gigCity].where((s) => s.isNotEmpty).join(' · ');
    } else if (tourName.isNotEmpty) {
      subtitle = '$tourName${artist.isNotEmpty ? ' · $artist' : ''}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending
              ? Colors.orange.withOpacity(0.4)
              : isAwaitingConfirm
                  ? Colors.amber.withOpacity(0.4)
                  : CssTheme.outline,
          width: isPending || isAwaitingConfirm ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style:
                            const TextStyle(color: CssTheme.textMuted),
                      ),
                  ],
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.route,
                label: routeLabel,
              ),
              _InfoChip(
                icon: Icons.calendar_today,
                label: '${_formatDate(dateFrom)} – ${_formatDate(dateTo)}',
              ),
              if (pax != null)
                _InfoChip(
                  icon: Icons.people,
                  label: '$pax passengers',
                ),
              if (busCount != null && busCount > 1)
                _InfoChip(
                  icon: Icons.directions_bus,
                  label: '${busCount}x nightliner',
                ),
              if (trailer)
                _InfoChip(
                  icon: Icons.rv_hookup,
                  label: 'Trailer',
                ),
              if (createdAt != null)
                _InfoChip(
                  icon: Icons.access_time,
                  label:
                      'Received ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(createdAt).toLocal())}',
                ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CssTheme.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                notes,
                style: const TextStyle(
                  fontSize: 13,
                  color: CssTheme.textMuted,
                ),
              ),
            ),
          ],
          // Availability section
          if (dateFrom.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loadingAvailability
                ? const Row(
                    children: [
                      SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Checking availability...', style: TextStyle(fontSize: 12, color: CssTheme.textMuted)),
                    ],
                  )
                : _availability != null
                    ? Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _availability!.entries.map((e) {
                          final available = e.value;
                          return Chip(
                            label: Text(
                              e.key,
                              style: TextStyle(
                                fontSize: 11,
                                color: available ? Colors.green.shade800 : Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: available
                                ? Colors.green.withOpacity(0.12)
                                : Colors.red.withOpacity(0.12),
                            side: BorderSide(
                              color: available
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.red.withOpacity(0.3),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      )
                    : const SizedBox.shrink(),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: widget.onCreateOffer,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Create offer'),
                ),
              ],
            ),
          ],
          if (status == 'accepted_by_client') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onDecline,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Avslå'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: widget.onAccept,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Bekreft'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
          ],
          // Archive button for terminal statuses (not in archive view)
          if (!widget.isArchiveView &&
              ['quoted', 'accepted', 'confirmed', 'rejected', 'declined', 'cancelled'].contains(status)) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onArchive,
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Archive'),
                ),
              ],
            ),
          ],
          // Restore + Delete buttons in archive view
          if (widget.isArchiveView) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onRestore,
                  icon: const Icon(Icons.unarchive_outlined, size: 16),
                  label: const Text('Restore'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_forever, size: 16),
                  label: const Text('Delete permanently'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '';
    try {
      return DateFormat('dd.MM.yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }
}

class _BadgeChip extends StatelessWidget {
  final int count;
  const _BadgeChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: CssTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: CssTheme.text),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'pending': Colors.orange,
      'quoted': Colors.blue,
      'offer_sent': Colors.teal,
      'accepted_by_client': Colors.amber,
      'accepted': Colors.green,
      'confirmed': Colors.green,
      'declined': Colors.red,
      'rejected': Colors.red,
      'cancelled': Colors.red,
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
