import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/meeting_service.dart';
import '../../state/active_company.dart';

class MeetingWizardPage extends StatefulWidget {
  const MeetingWizardPage({super.key});

  @override
  State<MeetingWizardPage> createState() => _MeetingWizardPageState();
}

class _MeetingWizardPageState extends State<MeetingWizardPage> {
  int _step = 0; // 0=Info, 1=Deltakere, 2=Agenda
  bool _saving = false;

  // Step 1 — Info
  final _titleCtrl = TextEditingController();
  DateTime? _date;
  final _startTimeCtrl = TextEditingController();
  final _endTimeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  // Step 2 — Participants
  List<Map<String, dynamic>> _allMembers = [];
  final Set<String> _selectedUserIds = {};

  // Step 3 — Agenda
  final List<_AgendaItemDraft> _agendaItems = [];
  List<Map<String, dynamic>> _templates = [];

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadTemplates();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _addressCtrl.dispose();
    _postalCodeCtrl.dispose();
    _cityCtrl.dispose();
    _commentCtrl.dispose();
    for (final item in _agendaItems) {
      item.titleCtrl.dispose();
      item.descCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMembers() async {
    if (_companyId == null) return;
    try {
      _allMembers = await MeetingService.getCompanyMembers(_companyId!);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Load members error: $e');
    }
  }

  Future<void> _loadTemplates() async {
    if (_companyId == null) return;
    try {
      _templates = await MeetingService.listTemplates(_companyId!);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Load templates error: $e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final initial = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      ctrl.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  void _addAgendaItem() {
    setState(() {
      _agendaItems.add(_AgendaItemDraft());
    });
  }

  void _addFromTemplate(Map<String, dynamic> template) {
    final item = _AgendaItemDraft();
    item.titleCtrl.text = template['title'] ?? '';
    item.type = template['item_type'] ?? 'none';
    item.descCtrl.text = template['description'] ?? '';
    setState(() => _agendaItems.add(item));
  }

  Future<void> _pickFiles(int index) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      if (file.bytes != null) {
        setState(() {
          _agendaItems[index].files.add((
            name: file.name,
            bytes: file.bytes!,
            contentType: _guessContentType(file.name),
          ));
        });
      }
    }
  }

  String _guessContentType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    }[ext] ?? 'application/octet-stream';
  }

  Future<void> _finalize() async {
    if (_companyId == null) return;
    if (_titleCtrl.text.trim().isEmpty || _date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn tittel og dato')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // 1. Create meeting
      final meeting = await MeetingService.createMeeting(
        companyId: _companyId!,
        title: _titleCtrl.text.trim(),
        date: DateFormat('yyyy-MM-dd').format(_date!),
        startTime: _startTimeCtrl.text.isNotEmpty ? '${_startTimeCtrl.text}:00' : null,
        endTime: _endTimeCtrl.text.isNotEmpty ? '${_endTimeCtrl.text}:00' : null,
        address: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
        postalCode: _postalCodeCtrl.text.trim().isNotEmpty ? _postalCodeCtrl.text.trim() : null,
        city: _cityCtrl.text.trim().isNotEmpty ? _cityCtrl.text.trim() : null,
        comment: _commentCtrl.text.trim().isNotEmpty ? _commentCtrl.text.trim() : null,
      );

      final meetingId = meeting['id'] as String;

      // 2. Add participants
      if (_selectedUserIds.isNotEmpty) {
        await MeetingService.setParticipants(meetingId, _selectedUserIds.toList());
      }

      // 3. Add agenda items + files
      for (int i = 0; i < _agendaItems.length; i++) {
        final draft = _agendaItems[i];
        if (draft.titleCtrl.text.trim().isEmpty) continue;

        final agendaItem = await MeetingService.addAgendaItem(
          meetingId: meetingId,
          title: draft.titleCtrl.text.trim(),
          itemType: draft.type,
          description: draft.descCtrl.text.trim().isNotEmpty ? draft.descCtrl.text.trim() : null,
          assignedTo: draft.assignedTo,
          sortOrder: i,
        );

        // Upload files
        for (final file in draft.files) {
          await MeetingService.uploadAgendaFile(
            agendaItemId: agendaItem['id'] as String,
            bytes: file.bytes,
            fileName: file.name,
            contentType: file.contentType,
          );
        }
      }

      // 4. Finalize
      await MeetingService.updateStatus(meetingId, 'finalized');

      if (mounted) {
        context.go('/m/meetings/$meetingId');
      }
    } catch (e) {
      debugPrint('Finalize error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/m/gigs'),
              ),
              const SizedBox(width: 8),
              const Text('Nytt møte',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 16),

          // Step indicator
          Row(
            children: [
              _stepChip(0, 'Info'),
              const SizedBox(width: 8),
              _stepChip(1, 'Deltakere'),
              const SizedBox(width: 8),
              _stepChip(2, 'Agenda'),
            ],
          ),
          const SizedBox(height: 20),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: _step == 0
                  ? _buildInfoStep()
                  : _step == 1
                      ? _buildParticipantsStep()
                      : _buildAgendaStep(),
            ),
          ),

          // Bottom buttons
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('Tilbake'),
                ),
              const SizedBox(width: 12),
              if (_step < 2)
                FilledButton(
                  onPressed: () => setState(() => _step++),
                  child: const Text('Neste'),
                ),
              if (_step == 2)
                FilledButton(
                  onPressed: _saving ? null : _finalize,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Ferdigstill møte'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepChip(int step, String label) {
    final active = _step == step;
    final done = _step > step;
    return GestureDetector(
      onTap: () => setState(() => _step = step),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.black : done ? Colors.green.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done) const Icon(Icons.check, size: 16, color: Colors.green),
            if (done) const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.black87,
                )),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // STEP 1: INFO
  // ---------------------------------------------------------------

  Widget _buildInfoStep() {
    return SizedBox(
      width: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Tittel'),
          TextField(controller: _titleCtrl, decoration: _dec('Tittel på møtet')),
          const SizedBox(height: 16),
          _label('Dato'),
          GestureDetector(
            onTap: _pickDate,
            child: AbsorbPointer(
              child: TextField(
                decoration: _dec(_date != null
                    ? DateFormat('dd.MM.yyyy').format(_date!)
                    : 'Velg dato'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Fra'),
                  GestureDetector(
                    onTap: () => _pickTime(_startTimeCtrl),
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _startTimeCtrl,
                        decoration: _dec('HH:mm'),
                      ),
                    ),
                  ),
                ],
              )),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Til'),
                  GestureDetector(
                    onTap: () => _pickTime(_endTimeCtrl),
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _endTimeCtrl,
                        decoration: _dec('HH:mm'),
                      ),
                    ),
                  ),
                ],
              )),
            ],
          ),
          const SizedBox(height: 16),
          _label('Adresse'),
          TextField(controller: _addressCtrl, decoration: _dec('Adresse')),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Postnr'),
                    TextField(controller: _postalCodeCtrl, decoration: _dec('Postnr')),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Sted'),
                  TextField(controller: _cityCtrl, decoration: _dec('By / sted')),
                ],
              )),
            ],
          ),
          const SizedBox(height: 16),
          _label('Kommentar'),
          TextField(
            controller: _commentCtrl,
            decoration: _dec('Kommentar til møtet'),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // STEP 2: PARTICIPANTS
  // ---------------------------------------------------------------

  Widget _buildParticipantsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary of Step 1
        _summaryBox(),
        const SizedBox(height: 20),

        const Text('Velg deltakere',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),

        ..._allMembers.map((m) {
          final userId = m['id'] as String;
          final name = m['name'] as String? ?? m['email'] as String? ?? 'Ukjent';
          final selected = _selectedUserIds.contains(userId);
          return CheckboxListTile(
            value: selected,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: m['role'] != null ? Text(m['role'] as String) : null,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedUserIds.add(userId);
                } else {
                  _selectedUserIds.remove(userId);
                }
              });
            },
          );
        }),
      ],
    );
  }

  Widget _summaryBox() {
    final date = _date != null ? DateFormat('dd.MM.yyyy').format(_date!) : '—';
    final time = [
      if (_startTimeCtrl.text.isNotEmpty) _startTimeCtrl.text,
      if (_endTimeCtrl.text.isNotEmpty) '– ${_endTimeCtrl.text}',
    ].join(' ');
    final location = [_addressCtrl.text, _postalCodeCtrl.text, _cityCtrl.text]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_titleCtrl.text.isNotEmpty ? _titleCtrl.text : '(Uten tittel)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$date${time.isNotEmpty ? '  $time' : ''}',
              style: const TextStyle(color: Colors.black54)),
          if (location.isNotEmpty)
            Text(location, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // STEP 3: AGENDA
  // ---------------------------------------------------------------

  Widget _buildAgendaStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryBox(),
        const SizedBox(height: 20),

        Row(
          children: [
            const Text('Agenda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (_templates.isNotEmpty)
              PopupMenuButton<Map<String, dynamic>>(
                tooltip: 'Legg til fra mal',
                onSelected: _addFromTemplate,
                itemBuilder: (_) => _templates
                    .map((t) => PopupMenuItem(
                          value: t,
                          child: Text(t['title'] ?? ''),
                        ))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_add, size: 16),
                      SizedBox(width: 6),
                      Text('Fra mal', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _addAgendaItem,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Legg til sak'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _agendaItems.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _agendaItems.removeAt(oldIndex);
              _agendaItems.insert(newIndex, item);
            });
          },
          itemBuilder: (_, i) {
            final item = _agendaItems[i];
            return Container(
              key: ValueKey('agenda-$i-${item.hashCode}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Sak ${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      // Type dropdown
                      DropdownButton<String>(
                        value: item.type,
                        underline: const SizedBox(),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('Ingen type')),
                          DropdownMenuItem(value: 'information', child: Text('Informasjon')),
                          DropdownMenuItem(value: 'decision', child: Text('Beslutning')),
                          DropdownMenuItem(value: 'other', child: Text('Annet')),
                        ],
                        onChanged: (v) => setState(() => item.type = v ?? 'none'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _agendaItems[i].titleCtrl.dispose();
                          _agendaItems[i].descCtrl.dispose();
                          _agendaItems.removeAt(i);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: item.titleCtrl,
                    decoration: _dec('Tittel'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: item.descCtrl,
                    decoration: _dec('Beskrivelse (valgfri)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  // Assigned to
                  DropdownButton<String?>(
                    value: item.assignedTo,
                    hint: const Text('Ansvarlig'),
                    underline: const SizedBox(),
                    isDense: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Ingen')),
                      ..._allMembers.map((m) => DropdownMenuItem(
                            value: m['id'] as String,
                            child: Text(m['name'] as String? ?? 'Ukjent'),
                          )),
                    ],
                    onChanged: (v) => setState(() => item.assignedTo = v),
                  ),
                  const SizedBox(height: 8),
                  // Files
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ...item.files.asMap().entries.map((e) => Chip(
                            label: Text(e.value.name, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => setState(() => item.files.removeAt(e.key)),
                          )),
                      ActionChip(
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: const Text('Legg til filer'),
                        onPressed: () => _pickFiles(i),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: Colors.black54)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );
}

// ---------------------------------------------------------------
// DRAFT MODEL
// ---------------------------------------------------------------

class _AgendaItemDraft {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  String type = 'none';
  String? assignedTo;
  final List<({String name, Uint8List bytes, String contentType})> files = [];
}
