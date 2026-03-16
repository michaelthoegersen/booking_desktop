import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/meeting_service.dart';
import '../../state/active_company.dart';

class MgmtMeetingsPage extends StatefulWidget {
  const MgmtMeetingsPage({super.key});

  @override
  State<MgmtMeetingsPage> createState() => _MgmtMeetingsPageState();
}

class _MgmtMeetingsPageState extends State<MgmtMeetingsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _meetings = [];
  String _statusFilter = 'all';

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
      _meetings = await MeetingService.listMeetings(_companyId!);
    } catch (e) {
      debugPrint('Meetings load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _meetings;
    return _meetings.where((m) => m['status'] == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('Møter',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.go('/m/meetings/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nytt møte'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Status filters
          Row(
            children: [
              ...[
                ('all', 'Alle'),
                ('draft', 'Utkast'),
                ('finalized', 'Ferdigstilt'),
                ('in_progress', 'Pågår'),
                ('completed', 'Fullført'),
              ].map((e) {
                final active = _statusFilter == e.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: InkWell(
                    onTap: () => setState(() => _statusFilter = e.$1),
                    child: Text(
                      e.$2,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        decoration: active
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationThickness: 2,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('Ingen møter',
                            style: TextStyle(color: Colors.black45)))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final m = _filtered[i];
                          return _MeetingRow(
                            meeting: m,
                            onTap: () => context.go('/m/meetings/${m['id']}'),
                            onDelete: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Slett møte?'),
                                  content: Text(
                                      'Er du sikker på at du vil slette "${m['title']}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Avbryt'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('Slett'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await MeetingService.deleteMeeting(
                                    m['id'] as String);
                                _load();
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final Map<String, dynamic> meeting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MeetingRow({
    required this.meeting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = meeting['title'] ?? '';
    final date = meeting['date'] != null
        ? DateFormat('dd.MM.yyyy').format(DateTime.parse(meeting['date']))
        : '';
    final status = meeting['status'] ?? 'draft';
    final city = meeting['city'] ?? '';
    final participants = meeting['meeting_participants'] as List? ?? [];

    final statusLabel = const {
      'draft': 'Utkast',
      'finalized': 'Ferdigstilt',
      'in_progress': 'Pågår',
      'completed': 'Fullført',
    }[status] ?? status;

    final statusColor = const {
      'draft': Colors.orange,
      'finalized': Colors.blue,
      'in_progress': Colors.green,
      'completed': Colors.grey,
    }[status] ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            // Date
            SizedBox(
              width: 90,
              child: Text(date,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black54)),
            ),
            const SizedBox(width: 16),

            // Title + city
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (city.isNotEmpty)
                    Text(city,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45)),
                ],
              ),
            ),

            // Participant count
            if (participants.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, size: 16, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text('${participants.length}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45)),
                  ],
                ),
              ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ),

            // Delete menu
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red),
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
