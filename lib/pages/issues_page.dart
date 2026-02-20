import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../ui/css_theme.dart';

class IssuesPage extends StatefulWidget {
  const IssuesPage({super.key});

  @override
  State<IssuesPage> createState() => _IssuesPageState();
}

class _IssuesPageState extends State<IssuesPage> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _issues = [];
  bool _loading = true;
  String _filterStatus = 'all';
  bool _filterCritical = false;

  Map<String, dynamic>? _selected;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
    _markAllSeen();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _markAllSeen() async {
    try {
      await _supabase
          .from('issues')
          .update({'seen_by_admin': true})
          .or('seen_by_admin.is.null,seen_by_admin.eq.false');
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('issues-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'issues',
          callback: (payload) => _load(),
        )
        .subscribe();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('issues')
          .select('*')
          .order('created_at', ascending: false);

      final issues = List<Map<String, dynamic>>.from(data);

      final userIds = issues
          .map((i) => i['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, String> nameMap = {};
      if (userIds.isNotEmpty) {
        final profiles = await _supabase
            .from('profiles')
            .select('id, name')
            .inFilter('id', userIds);
        for (final p in profiles) {
          nameMap[p['id'] as String] = (p['name'] ?? '') as String;
        }
      }

      for (final issue in issues) {
        final uid = issue['user_id'] as String?;
        issue['_driver_name'] = uid != null ? (nameMap[uid] ?? '') : '';
      }

      setState(() => _issues = issues);
    } catch (e) {
      debugPrint('Load issues error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _issues.where((issue) {
      final statusMatch = _filterStatus == 'all' ||
          (issue['status'] ?? 'open') == _filterStatus;
      final criticalMatch = !_filterCritical || issue['critical'] == true;
      return statusMatch && criticalMatch;
    }).toList();
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'in_progress':
        return const Color(0xFF3498DB);
      case 'resolved':
        return const Color(0xFF2ECC71);
      default:
        return const Color(0xFFF5A623);
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Open';
    }
  }

  String _categoryLabel(String? cat) {
    const map = {
      'motor': 'Engine',
      'brakes': 'Brakes',
      'tires': 'Tires',
      'electric': 'Electrical',
      'interior': 'Interior',
      'other': 'Other',
    };
    return map[cat] ?? (cat ?? '');
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _driverName(Map<String, dynamic> issue) {
    return (issue['_driver_name'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: list panel ──
          SizedBox(
            width: 360,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildFilterBar(cs),
                  Expanded(child: _buildList(cs)),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),

          // ── Right: detail panel ──
          Expanded(
            child: _selected == null
                ? const SizedBox.shrink()
                : Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: _IssueDetail(
                      key: ValueKey(_selected!['id']),
                      issue: _selected!,
                      statusLabel: _statusLabel,
                      categoryLabel: _categoryLabel,
                      statusColor: _statusColor,
                      driverName: _driverName(_selected!),
                      fmtDate: _fmtDate,
                      onSaved: (updated) {
                        final idx = _issues
                            .indexWhere((i) => i['id'] == updated['id']);
                        if (idx != -1) {
                          setState(() {
                            _issues[idx] = updated;
                            _selected = updated;
                          });
                        }
                      },
                      onDeleted: () {
                        setState(() {
                          _issues.removeWhere(
                              (i) => i['id'] == _selected!['id']);
                          _selected = null;
                        });
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Issue Reports',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (key, label) in [
                ('all', 'All'),
                ('open', 'Open'),
                ('in_progress', 'In Progress'),
                ('resolved', 'Resolved'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _filterStatus == key,
                  onSelected: (_) => setState(() {
                    _filterStatus = key;
                    _selected = null;
                  }),
                  selectedColor: CssTheme.header,
                  backgroundColor: cs.surfaceContainerLowest,
                  side: BorderSide(color: cs.outlineVariant),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _filterStatus == key
                        ? Colors.white
                        : CssTheme.text,
                  ),
                ),
              FilterChip(
                label: const Text('Critical'),
                selected: _filterCritical,
                selectedColor: Colors.red.shade100,
                backgroundColor: cs.surfaceContainerLowest,
                side: BorderSide(color: cs.outlineVariant),
                checkmarkColor: Colors.red,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      _filterCritical ? Colors.red : CssTheme.text,
                ),
                onSelected: (v) => setState(() {
                  _filterCritical = v;
                  _selected = null;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _filtered;

    if (items.isEmpty) {
      return const Center(
        child: Text('No reports',
            style: TextStyle(color: CssTheme.textMuted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (context, i) {
        final issue = items[i];
        final isSelected = _selected?['id'] == issue['id'];
        final critical = issue['critical'] == true;
        final status = issue['status'] ?? 'open';

        return InkWell(
          onTap: () => setState(() => _selected = issue),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            color: isSelected
                ? Colors.black.withOpacity(0.06)
                : Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _categoryLabel(issue['category']),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                    if (critical)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.red.shade200),
                        ),
                        child: Text('Critical',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade700)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (issue['description'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: CssTheme.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_driverName(issue)}  ·  ${_fmtDate(issue['created_at'])}',
                  style: const TextStyle(
                      fontSize: 11, color: CssTheme.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Detail panel ───────────────────────────────────────────────────────────────

class _IssueDetail extends StatefulWidget {
  final Map<String, dynamic> issue;
  final String Function(String?) statusLabel;
  final String Function(String?) categoryLabel;
  final Color Function(String?) statusColor;
  final String driverName;
  final String Function(String?) fmtDate;
  final void Function(Map<String, dynamic>) onSaved;
  final VoidCallback onDeleted;

  const _IssueDetail({
    super.key,
    required this.issue,
    required this.statusLabel,
    required this.categoryLabel,
    required this.statusColor,
    required this.driverName,
    required this.fmtDate,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  State<_IssueDetail> createState() => _IssueDetailState();
}

class _IssueDetailState extends State<_IssueDetail> {
  final _supabase = Supabase.instance.client;
  late String _status;
  late final TextEditingController _noteCtrl;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _status = widget.issue['status'] ?? 'open';
    _noteCtrl = TextEditingController(
        text: (widget.issue['resolution_note'] ?? '').toString());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete report'),
        content: const Text(
            'Are you sure you want to delete this report? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await _supabase
          .from('issues')
          .delete()
          .eq('id', widget.issue['id']);
      widget.onDeleted();
    } catch (e) {
      debugPrint('Delete issue error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = {
        'status': _status,
        'resolution_note': _noteCtrl.text.trim(),
      };

      await _supabase
          .from('issues')
          .update(updated)
          .eq('id', widget.issue['id']);

      if (_status != (widget.issue['status'] ?? 'open')) {
        final userId = widget.issue['user_id'] as String?;
        if (userId != null) {
          final label = _status == 'resolved'
              ? 'Issue resolved'
              : 'Issue updated';
          final body = _noteCtrl.text.trim().isNotEmpty
              ? _noteCtrl.text.trim()
              : 'Status changed to: ${widget.statusLabel(_status)}';

          await NotificationService.sendToUserId(
            userId: userId,
            title: label,
            body: body,
          );
        }
      }

      final newIssue = Map<String, dynamic>.from(widget.issue)
        ..addAll(updated);
      widget.onSaved(newIssue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      debugPrint('Save issue error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _statusColor(String? status) => widget.statusColor(status);

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final critical = issue['critical'] == true;
    final imageUrl = issue['image_url'] as String?;
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoryLabel(issue['category']),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.driverName}  ·  ${widget.fmtDate(issue['created_at'])}',
                      style: const TextStyle(
                          color: CssTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (critical)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text('Critical',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700)),
                ),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 20),

          // ── Description ──
          _Label('Description'),
          const SizedBox(height: 8),
          Text(
            (issue['description'] ?? '').toString(),
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),

          // ── Image ──
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 20),
            _Label('Photo'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(32),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Text('Could not load image',
                          style:
                              TextStyle(color: CssTheme.textMuted)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Status ──
          _Label('Status'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(
                  value: 'in_progress', label: Text('In Progress')),
              ButtonSegment(
                  value: 'resolved', label: Text('Resolved')),
            ],
            selected: {_status},
            onSelectionChanged: (v) =>
                setState(() => _status = v.first),
            style: ButtonStyle(
              backgroundColor:
                  WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _statusColor(_status);
                }
                return null;
              }),
              foregroundColor:
                  WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return null;
              }),
            ),
          ),

          const SizedBox(height: 20),

          // ── Note ──
          _Label('Note to driver (shown in app)'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Describe what was done or what is happening...',
            ),
          ),

          const SizedBox(height: 24),

          // ── Buttons ──
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving
                        ? 'Saving...'
                        : 'Save and notify driver'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _deleting ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  icon: _deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: CssTheme.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}
