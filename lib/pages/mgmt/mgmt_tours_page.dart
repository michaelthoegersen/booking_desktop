import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';

class MgmtToursPage extends StatefulWidget {
  const MgmtToursPage({super.key});

  @override
  State<MgmtToursPage> createState() => _MgmtToursPageState();
}

class _MgmtToursPageState extends State<MgmtToursPage> {
  final _sb = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _companyId;
  List<Map<String, dynamic>> _tours = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      final profile = await _sb
          .from('profiles')
          .select('company_id')
          .eq('id', uid)
          .maybeSingle();
      _companyId = profile?['company_id'] as String?;

      if (_companyId == null) {
        setState(() => _loading = false);
        return;
      }

      final tours = await _sb
          .from('management_tours')
          .select('*')
          .eq('company_id', _companyId!)
          .order('created_at', ascending: false);

      _tours = List<Map<String, dynamic>>.from(tours);
    } catch (e) {
      debugPrint('Tours load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _tours;
    final q = _search.toLowerCase();
    return _tours
        .where((t) =>
            (t['name'] as String? ?? '').toLowerCase().contains(q) ||
            (t['artist'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _confirmDelete(Map<String, dynamic> tour) async {
    final name = tour['name'] as String? ?? 'denne touren';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett tour'),
        content: Text(
          'Er du sikker på at du vil slette "$name"?\n\n'
          'Alle shows, itinerary og teammedlemmer tilknyttet touren vil også slettes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _sb
          .from('management_tours')
          .delete()
          .eq('id', tour['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

  Future<void> _openNewTourDialog() async {
    final nameCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    String status = 'planning';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New Tour'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tour name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: artistCtrl,
                  decoration: const InputDecoration(labelText: 'Artist'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ['planning', 'active', 'completed', 'cancelled']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setS(() => status = v ?? 'planning'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(startDate != null
                            ? DateFormat('dd.MM.yyyy').format(startDate!)
                            : 'Start date'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setS(() => startDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(endDate != null
                            ? DateFormat('dd.MM.yyyy').format(endDate!)
                            : 'End date'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setS(() => endDate = d);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    artistCtrl.text.trim().isEmpty) {
                  return;
                }
                try {
                  await _sb.from('management_tours').insert({
                    'company_id': _companyId,
                    'name': nameCtrl.text.trim(),
                    'artist': artistCtrl.text.trim(),
                    'status': status,
                    if (startDate != null)
                      'tour_start':
                          DateFormat('yyyy-MM-dd').format(startDate!),
                    if (endDate != null)
                      'tour_end': DateFormat('yyyy-MM-dd').format(endDate!),
                    'created_by': _sb.auth.currentUser?.id,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Create tour error: $e');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
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
              Text(
                'Tours',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search tours…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openNewTourDialog,
                icon: const Icon(Icons.add),
                label: const Text('New tour'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _search.isNotEmpty
                              ? 'No tours match your search'
                              : 'No tours yet. Create your first tour!',
                          style: const TextStyle(color: CssTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final tour = _filtered[i];
                          return _TourRow(
                            tour: tour,
                            onTap: () =>
                                context.go('/m/tours/${tour['id']}'),
                            onDelete: () => _confirmDelete(tour),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _TourRow extends StatelessWidget {
  final Map<String, dynamic> tour;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TourRow({required this.tour, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = tour['name'] as String? ?? '';
    final artist = tour['artist'] as String? ?? '';
    final status = tour['status'] as String? ?? 'planning';
    final start = tour['tour_start'] as String?;
    final end = tour['tour_end'] as String?;

    String dateRange = '';
    if (start != null && end != null) {
      dateRange =
          '${DateFormat('dd.MM.yyyy').format(DateTime.parse(start))} – ${DateFormat('dd.MM.yyyy').format(DateTime.parse(end))}';
    } else if (start != null) {
      dateRange =
          'From ${DateFormat('dd.MM.yyyy').format(DateTime.parse(start))}';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
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
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    artist,
                    style: const TextStyle(color: CssTheme.textMuted),
                  ),
                  if (dateRange.isNotEmpty)
                    Text(
                      dateRange,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CssTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            _StatusBadge(status: status),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: CssTheme.textMuted),
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Slett', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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
