import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/css_theme.dart';

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
  String _filterStatus = 'pending';

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
          .select('*, companies(name), management_tours(name, artist)');

      final data = _filterStatus == 'all'
          ? await query.order('created_at', ascending: false)
          : await query
              .eq('status', _filterStatus)
              .order('created_at', ascending: false);

      _requests = List<Map<String, dynamic>>.from(data);

      // Update badge with pending count
      final pending = await _sb
          .from('bus_requests')
          .select('id')
          .eq('status', 'pending');
      busRequestsBadgeNotifier.value = (pending as List).length;
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
    // Navigate to new offer page with bus request context
    // Pre-populate by passing query parameters
    final dateFrom = request['date_from'] as String?;
    final dateTo = request['date_to'] as String?;
    final fromCity = request['from_city'] as String? ?? '';
    final toCity = request['to_city'] as String? ?? '';
    final company = request['companies'] as Map<String, dynamic>?;
    final companyName = company?['name'] as String? ?? '';

    // Update status to quoted first
    await _sb.from('bus_requests').update({
      'status': 'quoted',
    }).eq('id', request['id']);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Request marked as quoted. Create offer for $companyName — $fromCity → $toCity ($dateFrom to $dateTo)',
          ),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'New offer',
            onPressed: () => context.go('/new'),
          ),
        ),
      );
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
                segments: const [
                  ButtonSegment(value: 'pending', label: Text('Pending')),
                  ButtonSegment(value: 'quoted', label: Text('Quoted')),
                  ButtonSegment(value: 'all', label: Text('All')),
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _BusRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCreateOffer;
  final VoidCallback onReject;

  const _BusRequestCard({
    required this.request,
    required this.onCreateOffer,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final company = request['companies'] as Map<String, dynamic>?;
    final companyName = company?['name'] as String? ?? 'Unknown company';
    final tour = request['management_tours'] as Map<String, dynamic>?;
    final tourName = tour?['name'] as String? ?? '';
    final artist = tour?['artist'] as String? ?? '';
    final dateFrom = request['date_from'] as String? ?? '';
    final dateTo = request['date_to'] as String? ?? '';
    final fromCity = request['from_city'] as String? ?? '';
    final toCity = request['to_city'] as String? ?? '';
    final pax = request['pax'] as int?;
    final notes = request['notes'] as String? ?? '';
    final status = request['status'] as String? ?? 'pending';
    final createdAt = request['created_at'] as String?;

    final isPending = status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending
              ? Colors.orange.withOpacity(0.4)
              : CssTheme.outline,
          width: isPending ? 2 : 1,
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
                    if (tourName.isNotEmpty)
                      Text(
                        '$tourName${artist.isNotEmpty ? ' · $artist' : ''}',
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
                label: '$fromCity → $toCity',
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
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onCreateOffer,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Create offer'),
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
