import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/meeting_service.dart';
import '../../widgets/agora_meeting_view.dart';
import '../../widgets/agora_meeting_stub.dart'
    if (dart.library.js_interop) '../../widgets/agora_meeting_view_web.dart';

class MeetingLivePage extends StatefulWidget {
  final String meetingId;
  const MeetingLivePage({super.key, required this.meetingId});

  @override
  State<MeetingLivePage> createState() => _MeetingLivePageState();
}

class _MeetingLivePageState extends State<MeetingLivePage> {
  bool _loading = true;
  Map<String, dynamic>? _meeting;
  List<Map<String, dynamic>> _agendaItems = [];
  Map<String, String> _userNames = {};
  int _currentIndex = 0;

  Timer? _autoSaveTimer;
  final _notesCtrl = TextEditingController();
  String? _lastSavedNotes;

  bool _videoActive = false;
  bool _videoFullscreen = false;
  String _myName = '';

  @override
  void initState() {
    super.initState();
    _load();
    _notesCtrl.addListener(_onNotesChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _saveCurrentNotes();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onNotesChanged() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _saveCurrentNotes);
  }

  Future<void> _saveCurrentNotes() async {
    if (_agendaItems.isEmpty) return;
    final item = _agendaItems[_currentIndex];
    final notes = _notesCtrl.text;
    if (notes == _lastSavedNotes) return;

    try {
      await MeetingService.updateAgendaNotes(item['id'] as String, notes);
      _lastSavedNotes = notes;
      _agendaItems[_currentIndex]['notes'] = notes;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Auto-save error: $e');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final meeting = await MeetingService.getMeeting(widget.meetingId);
      _meeting = meeting;

      _agendaItems = List<Map<String, dynamic>>.from(
          meeting['meeting_agenda_items'] ?? []);
      _agendaItems.sort((a, b) =>
          (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

      // User names
      final participants = List<Map<String, dynamic>>.from(
          meeting['meeting_participants'] ?? []);
      final allUserIds = <String>{};
      for (final p in participants) {
        allUserIds.add(p['user_id'] as String);
      }
      for (final a in _agendaItems) {
        if (a['assigned_to'] != null) allUserIds.add(a['assigned_to'] as String);
      }

      if (allUserIds.isNotEmpty) {
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id, name')
            .inFilter('id', allUserIds.toList());
        _userNames = {
          for (final p in (profiles as List))
            p['id'] as String: (p['name'] as String?) ?? 'Ukjent',
        };
      }

      // Load notes for first item
      if (_agendaItems.isNotEmpty) {
        _notesCtrl.text = _agendaItems[0]['notes'] as String? ?? '';
        _lastSavedNotes = _notesCtrl.text;
      }

      // Get my display name
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId != null) {
        _myName = _userNames[myId] ?? '';
      }
    } catch (e) {
      debugPrint('Meeting live load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goToItem(int index) {
    if (index < 0 || index >= _agendaItems.length) return;
    _saveCurrentNotes();
    setState(() => _currentIndex = index);
    _notesCtrl.text = _agendaItems[index]['notes'] as String? ?? '';
    _lastSavedNotes = _notesCtrl.text;
  }

  void _startVideo() {
    setState(() => _videoActive = true);
  }

  Widget _buildVideoWidget({required VoidCallback onLeave}) {
    final channel = 'tourflow-${widget.meetingId}';
    final name = _myName.isNotEmpty ? _myName : 'Deltaker';
    if (kIsWeb) {
      return AgoraMeetingViewWeb(
        channelName: channel,
        displayName: name,
        onLeave: onLeave,
      );
    }
    return AgoraMeetingView(
      channelName: channel,
      displayName: name,
      onLeave: onLeave,
    );
  }

  Future<void> _endMeeting() async {
    _saveCurrentNotes();
    await MeetingService.updateStatus(widget.meetingId, 'completed');
    if (mounted) context.go('/m/meetings/${widget.meetingId}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_meeting == null || _agendaItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingen saker i agendaen'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/m/meetings/${widget.meetingId}'),
              child: const Text('Tilbake'),
            ),
          ],
        ),
      );
    }

    final currentItem = _agendaItems[_currentIndex];
    final itemTitle = currentItem['title'] ?? '';
    final itemType = currentItem['item_type'] ?? 'none';
    final description = currentItem['description'] ?? '';
    final assignedTo = currentItem['assigned_to'] != null
        ? _userNames[currentItem['assigned_to']] ?? ''
        : '';
    final files = List<Map<String, dynamic>>.from(
        currentItem['meeting_agenda_files'] ?? []);

    final typeLabel = const {
      'information': 'Informasjonssak',
      'decision': 'Vedtakssak',
      'other': 'Annet',
    }[itemType];

    final typeColor = const {
      'information': Colors.blue,
      'decision': Colors.orange,
      'other': Colors.purple,
    }[itemType] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/m/meetings/${widget.meetingId}'),
              ),
              const SizedBox(width: 8),
              Text(_meeting!['title'] ?? '',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_videoActive) ...[
                FilledButton.icon(
                  onPressed: () => setState(() => _videoFullscreen = !_videoFullscreen),
                  icon: Icon(_videoFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 18),
                  label: Text(_videoFullscreen ? 'Minimer' : 'Fullskjerm'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade700),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => setState(() {
                    _videoActive = false;
                    _videoFullscreen = false;
                  }),
                  icon: const Icon(Icons.videocam_off, size: 18),
                  label: const Text('Skjul video'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade700),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _startVideo,
                  icon: const Icon(Icons.videocam, size: 18),
                  label: const Text('Start videomøte'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _endMeeting,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Avslutt møte'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Video panel
          if (_videoActive && _videoFullscreen) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildVideoWidget(onLeave: () => setState(() {
                  _videoActive = false;
                  _videoFullscreen = false;
                })),
              ),
            ),
          ],

          if (_videoActive && !_videoFullscreen) ...[
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildVideoWidget(onLeave: () => setState(() {
                  _videoActive = false;
                })),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Main content (hidden in fullscreen)
          if (!_videoFullscreen)
          Expanded(
            flex: _videoActive ? 4 : 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- MAIN PANEL (70%) ----
                Expanded(
                  flex: 7,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Navigation
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentIndex > 0
                                  ? () => _goToItem(_currentIndex - 1)
                                  : null,
                            ),
                            Text('Sak ${_currentIndex + 1} av ${_agendaItems.length}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54)),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentIndex < _agendaItems.length - 1
                                  ? () => _goToItem(_currentIndex + 1)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Title + type badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(itemTitle,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w900)),
                            ),
                            if (typeLabel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: typeColor.withOpacity(0.3)),
                                ),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: typeColor)),
                              ),
                          ],
                        ),

                        if (assignedTo.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.person, size: 16, color: Colors.black45),
                              const SizedBox(width: 6),
                              Text('Ansvarlig: $assignedTo',
                                  style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ],

                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(description, style: const TextStyle(fontSize: 14)),
                        ],

                        if (files.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: files.map((f) => Chip(
                                  avatar: const Icon(Icons.attach_file, size: 14),
                                  label: Text(f['file_name'] ?? 'Fil',
                                      style: const TextStyle(fontSize: 12)),
                                )).toList(),
                          ),
                        ],

                        const SizedBox(height: 20),
                        const Text('Referat',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),

                        // Notes textarea
                        Expanded(
                          child: TextField(
                            controller: _notesCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText: 'Skriv referat her...',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              fillColor: Colors.grey.shade50,
                              filled: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // ---- SIDEBAR (30%) ----
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Alle saker',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _agendaItems.length,
                            itemBuilder: (_, i) {
                              final item = _agendaItems[i];
                              final hasNotes = (item['notes'] as String? ?? '').isNotEmpty;
                              final isActive = i == _currentIndex;
                              final assignee = item['assigned_to'] != null
                                  ? _userNames[item['assigned_to']] ?? ''
                                  : '';
                              final itemFiles = List.from(
                                  item['meeting_agenda_files'] ?? []);

                              return GestureDetector(
                                onTap: () => _goToItem(i),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.black
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: isActive
                                            ? Colors.black
                                            : Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      // Status indicator
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: hasNotes
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${i + 1}. ${item['title'] ?? ''}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: isActive
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (assignee.isNotEmpty)
                                              Text(
                                                assignee,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isActive
                                                      ? Colors.white70
                                                      : Colors.black45,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (itemFiles.isNotEmpty)
                                        Icon(Icons.attach_file,
                                            size: 14,
                                            color: isActive
                                                ? Colors.white54
                                                : Colors.black38),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
