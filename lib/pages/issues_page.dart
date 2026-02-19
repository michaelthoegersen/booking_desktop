import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';

class IssuesPage extends StatefulWidget {
  const IssuesPage({super.key});

  @override
  State<IssuesPage> createState() => _IssuesPageState();
}

class _IssuesPageState extends State<IssuesPage> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _issues = [];
  bool _loading = true;
  String _filterStatus = 'all'; // all | open | in_progress | resolved
  bool _filterCritical = false;

  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── data ──────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _supabase
          .from('issues')
          .select('*, profiles(name)')
          .order('created_at', ascending: false);

      final data = await q;
      setState(() => _issues = List<Map<String, dynamic>>.from(data));
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

  // ── helpers ───────────────────────────────────────────────

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
        return 'Under behandling';
      case 'resolved':
        return 'Løst';
      default:
        return 'Åpen';
    }
  }

  String _categoryLabel(String? cat) {
    const map = {
      'motor': 'Motor',
      'brakes': 'Bremser',
      'tires': 'Dekk',
      'electric': 'Elektrisk',
      'interior': 'Interiør',
      'other': 'Annet',
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
    final profile = issue['profiles'];
    if (profile is Map) return (profile['name'] ?? '').toString();
    return '';
  }

  // ── build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── left: list ──
        SizedBox(
          width: 380,
          child: Column(
            children: [
              _buildFilterBar(),
              Expanded(child: _buildList()),
            ],
          ),
        ),

        const VerticalDivider(width: 1),

        // ── right: detail ──
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text(
                    'Velg en rapport for å se detaljer',
                    style: TextStyle(color: Colors.black45),
                  ),
                )
              : _IssueDetail(
                  key: ValueKey(_selected!['id']),
                  issue: _selected!,
                  statusLabel: _statusLabel,
                  categoryLabel: _categoryLabel,
                  driverName: _driverName(_selected!),
                  fmtDate: _fmtDate,
                  onSaved: (updated) {
                    final idx =
                        _issues.indexWhere((i) => i['id'] == updated['id']);
                    if (idx != -1) {
                      setState(() {
                        _issues[idx] = updated;
                        _selected = updated;
                      });
                    }
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Feilrapporter',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Oppdater',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final (key, label) in [
                ('all', 'Alle'),
                ('open', 'Åpne'),
                ('in_progress', 'Pågående'),
                ('resolved', 'Løste'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _filterStatus == key,
                  onSelected: (_) => setState(() {
                    _filterStatus = key;
                    _selected = null;
                  }),
                  selectedColor: Colors.black,
                  labelStyle: TextStyle(
                    color: _filterStatus == key ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              FilterChip(
                label: const Text('Kritisk'),
                selected: _filterCritical,
                selectedColor: Colors.red.shade100,
                checkmarkColor: Colors.red,
                labelStyle: TextStyle(
                  color: _filterCritical ? Colors.red : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
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

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _filtered;

    if (items.isEmpty) {
      return const Center(
        child: Text('Ingen rapporter', style: TextStyle(color: Colors.black45)),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, i) {
        final issue = items[i];
        final isSelected = _selected?['id'] == issue['id'];
        final critical = issue['critical'] == true;
        final status = issue['status'] ?? 'open';

        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.black.withOpacity(0.06),
          onTap: () => setState(() => _selected = issue),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _categoryLabel(issue['category']),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              if (critical)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text('Kritisk',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700)),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.15),
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                (issue['description'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${_driverName(issue)}  ·  ${_fmtDate(issue['created_at'])}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Detail panel ──────────────────────────────────────────────────────────────

class _IssueDetail extends StatefulWidget {
  final Map<String, dynamic> issue;
  final String Function(String?) statusLabel;
  final String Function(String?) categoryLabel;
  final String driverName;
  final String Function(String?) fmtDate;
  final void Function(Map<String, dynamic>) onSaved;

  const _IssueDetail({
    super.key,
    required this.issue,
    required this.statusLabel,
    required this.categoryLabel,
    required this.driverName,
    required this.fmtDate,
    required this.onSaved,
  });

  @override
  State<_IssueDetail> createState() => _IssueDetailState();
}

class _IssueDetailState extends State<_IssueDetail> {
  final _supabase = Supabase.instance.client;
  late String _status;
  late final TextEditingController _noteCtrl;
  bool _saving = false;

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

      // Notify driver if status changed
      if (_status != (widget.issue['status'] ?? 'open')) {
        final userId = widget.issue['user_id'] as String?;
        if (userId != null) {
          final label = _status == 'resolved'
              ? 'Feilrapport løst'
              : 'Feilrapport oppdatert';
          final body = _noteCtrl.text.trim().isNotEmpty
              ? _noteCtrl.text.trim()
              : 'Status er endret til: ${widget.statusLabel(_status)}';

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
          const SnackBar(content: Text('Lagret')),
        );
      }
    } catch (e) {
      debugPrint('Save issue error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final critical = issue['critical'] == true;
    final imageUrl = issue['image_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── header ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.categoryLabel(issue['category']),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.driverName}  ·  ${widget.fmtDate(issue['created_at'])}',
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (critical)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text('Kritisk',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700)),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // ── description ──
            _Section(
              label: 'Beskrivelse',
              child: Text(
                (issue['description'] ?? '').toString(),
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),

            // ── image ──
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Section(
                label: 'Bilde',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Text('Kunne ikke laste bilde'),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── status ──
            _Section(
              label: 'Status',
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'open', label: Text('Åpen')),
                  ButtonSegment(
                      value: 'in_progress', label: Text('Under behandling')),
                  ButtonSegment(value: 'resolved', label: Text('Løst')),
                ],
                selected: {_status},
                onSelectionChanged: (v) =>
                    setState(() => _status = v.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _statusColor(_status);
                    }
                    return null;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── resolution note ──
            _Section(
              label: 'Notat til sjåfør (vises i appen)',
              child: TextField(
                controller: _noteCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Beskriv hva som ble gjort eller hva som skjer...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── save button ──
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Lagrer...' : 'Lagre og varsle sjåfør'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final Widget child;

  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black45,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
