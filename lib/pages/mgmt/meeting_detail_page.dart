import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/meeting_service.dart';
import '../../services/meeting_pdf_service.dart';
import '../../services/email_service.dart';
class MeetingDetailPage extends StatefulWidget {
  final String meetingId;
  const MeetingDetailPage({super.key, required this.meetingId});

  @override
  State<MeetingDetailPage> createState() => _MeetingDetailPageState();
}

class _MeetingDetailPageState extends State<MeetingDetailPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _meeting;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _agendaItems = [];
  Map<String, String> _userNames = {};

  Uint8List? _invitationPdf;
  Uint8List? _minutesPdf;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final meeting = await MeetingService.getMeeting(widget.meetingId);
      _meeting = meeting;

      _participants = List<Map<String, dynamic>>.from(
          meeting['meeting_participants'] ?? []);
      _agendaItems = List<Map<String, dynamic>>.from(
          meeting['meeting_agenda_items'] ?? []);
      _agendaItems.sort((a, b) =>
          (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

      // Load user names
      final allUserIds = <String>{};
      for (final p in _participants) {
        allUserIds.add(p['user_id'] as String);
      }
      for (final a in _agendaItems) {
        if (a['assigned_to'] != null) allUserIds.add(a['assigned_to'] as String);
      }

      if (allUserIds.isNotEmpty) {
        final profiles = await _sb
            .from('profiles')
            .select('id, name')
            .inFilter('id', allUserIds.toList());
        _userNames = {
          for (final p in (profiles as List))
            p['id'] as String: (p['name'] as String?) ?? 'Ukjent',
        };
      }
    } catch (e) {
      debugPrint('Meeting detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendInvitation() async {
    if (_meeting == null) return;

    // Show dialog for recipients + comment
    final result = await showDialog<({String recipients, String comment})>(
      context: context,
      builder: (ctx) {
        final commentCtrl = TextEditingController();

        return _SendDialog(
          title: 'Send innkalling',
          participantUserIds: _participants.map((p) => p['user_id'] as String).toList(),
          userNames: _userNames,
          commentCtrl: commentCtrl,
        );
      },
    );

    if (result == null || !mounted) return;

    try {
      // Generate PDF
      final pdfBytes = await MeetingPdfService.generateInvitation(
        meeting: _meeting!,
        participants: _participants,
        agendaItems: _agendaItems,
        userNames: _userNames,
      );
      setState(() => _invitationPdf = pdfBytes);

      // Build HTML email with RSVP buttons
      final title = _meeting!['title'] ?? 'Møte';
      final date = _meeting!['date'] != null
          ? DateFormat('dd.MM.yyyy').format(DateTime.parse(_meeting!['date']))
          : '';
      final startTime = _meeting!['start_time'] ?? '';
      final endTime = _meeting!['end_time'] ?? '';
      final city = _meeting!['city'] ?? '';

      final timeStr = [
        if (startTime.toString().isNotEmpty) startTime.toString().substring(0, 5),
        if (endTime.toString().isNotEmpty) '– ${endTime.toString().substring(0, 5)}',
      ].join(' ');

      final commentHtml = result.comment.isNotEmpty
          ? '<p style="color:#555;margin:12px 0;">${_escapeHtml(result.comment)}</p>'
          : '';

      // Send individual emails with personalized RSVP links
      for (final p in _participants) {
        final userId = p['user_id'] as String;

        final profile = await _sb
            .from('profiles')
            .select('email, name')
            .eq('id', userId)
            .maybeSingle();
        final email = profile?['email'] as String?;
        final name = profile?['name'] as String? ?? '';
        if (email == null || email.isEmpty) continue;

        final yesUrl = MeetingService.rsvpUrl(
            meetingId: widget.meetingId, userId: userId, response: 'attending');
        final noUrl = MeetingService.rsvpUrl(
            meetingId: widget.meetingId, userId: userId, response: 'not_attending');

        final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f5f5f5;">
  <div style="max-width:520px;margin:30px auto;background:#fff;border-radius:12px;overflow:hidden;border:1px solid #e0e0e0;">
    <div style="background:#1a1a1a;padding:24px 30px;">
      <h1 style="margin:0;font-size:20px;color:#fff;font-weight:800;">Innkalling til møte</h1>
    </div>
    <div style="padding:30px;">
      <p style="margin:0 0 6px;font-size:15px;color:#333;">Hei${name.isNotEmpty ? ' $name' : ''},</p>
      <p style="margin:0 0 20px;font-size:15px;color:#333;">Du er invitert til følgende møte:</p>

      <div style="background:#f8f8f8;border-radius:10px;padding:20px;margin-bottom:20px;border:1px solid #eee;">
        <h2 style="margin:0 0 10px;font-size:18px;color:#111;">${_escapeHtml(title)}</h2>
        <table style="font-size:14px;color:#444;">
          <tr><td style="padding:3px 12px 3px 0;font-weight:600;">Dato</td><td>$date</td></tr>
          ${timeStr.isNotEmpty ? '<tr><td style="padding:3px 12px 3px 0;font-weight:600;">Tid</td><td>$timeStr</td></tr>' : ''}
          ${city.isNotEmpty ? '<tr><td style="padding:3px 12px 3px 0;font-weight:600;">Sted</td><td>${_escapeHtml(city)}</td></tr>' : ''}
        </table>
      </div>

      $commentHtml

      <p style="margin:0 0 16px;font-size:15px;color:#333;font-weight:600;">Kan du delta?</p>

      <div style="text-align:center;margin:20px 0 24px;">
        <!--[if mso]>
        <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" style="height:44px;width:180px" arcsize="20%" strokecolor="#16a34a" fillcolor="#16a34a" href="$yesUrl">
        <w:anchorlock/>
        <center style="color:#fff;font-family:sans-serif;font-size:15px;font-weight:bold;">Ja, jeg kommer</center>
        </v:roundrect>
        <![endif]-->
        <!--[if !mso]><!-->
        <a href="$yesUrl" style="display:inline-block;padding:12px 32px;background:#16a34a;color:#fff;font-size:15px;font-weight:700;text-decoration:none;border-radius:8px;margin-right:12px;">Ja, jeg kommer</a>
        <!--<![endif]-->
        <!--[if mso]>
        <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" style="height:44px;width:180px" arcsize="20%" strokecolor="#dc2626" fillcolor="#dc2626" href="$noUrl">
        <w:anchorlock/>
        <center style="color:#fff;font-family:sans-serif;font-size:15px;font-weight:bold;">Nei, kan ikke</center>
        </v:roundrect>
        <![endif]-->
        <!--[if !mso]><!-->
        <a href="$noUrl" style="display:inline-block;padding:12px 32px;background:#dc2626;color:#fff;font-size:15px;font-weight:700;text-decoration:none;border-radius:8px;">Nei, kan ikke</a>
        <!--<![endif]-->
      </div>

      <div style="margin:16px 0 20px;padding:16px;background:#f0f7ff;border-radius:10px;border:1px solid #d0e3ff;">
        <p style="margin:0 0 8px;font-size:13px;font-weight:600;color:#1a56db;">Videomøte</p>
        <p style="margin:0;font-size:13px;color:#555;">Hvis videomøte startes, kan du bli med her:</p>
        <a href="https://meet.jit.si/tourflow-${widget.meetingId}" style="display:inline-block;margin-top:8px;padding:8px 16px;background:#1a56db;color:#fff;font-size:13px;font-weight:600;text-decoration:none;border-radius:6px;">Bli med i videomøte</a>
      </div>

      <p style="margin:0;font-size:13px;color:#999;">Vedlagt finner du innkallingen med full agenda.</p>
    </div>
    <div style="padding:16px 30px;background:#fafafa;border-top:1px solid #eee;">
      <p style="margin:0;font-size:12px;color:#999;">Mvh<br><strong style="color:#333;">Complete Drums</strong></p>
    </div>
  </div>
</body>
</html>''';

        await EmailService.sendEmailWithAttachment(
          to: email,
          subject: 'Innkalling: $title — $date',
          body: html,
          attachmentBytes: pdfBytes,
          attachmentFilename: 'Innkalling_${title.replaceAll(' ', '_')}.pdf',
          isHtml: true,
        );
      }

      // Save timestamp
      await _sb.from('meetings').update({
        'invitation_sent_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.meetingId);
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Innkalling sendt!')),
        );
      }
    } catch (e) {
      debugPrint('Send invitation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved sending: $e')),
        );
      }
    }
  }

  Future<void> _sendMinutes() async {
    if (_meeting == null) return;

    final result = await showDialog<({String recipients, String comment})>(
      context: context,
      builder: (ctx) {
        final commentCtrl = TextEditingController();
        return _SendDialog(
          title: 'Send referat',
          participantUserIds: _participants.map((p) => p['user_id'] as String).toList(),
          userNames: _userNames,
          commentCtrl: commentCtrl,
        );
      },
    );

    if (result == null || !mounted) return;

    try {
      final pdfBytes = await MeetingPdfService.generateMinutes(
        meeting: _meeting!,
        participants: _participants,
        agendaItems: _agendaItems,
        userNames: _userNames,
      );
      setState(() => _minutesPdf = pdfBytes);

      final title = _meeting!['title'] ?? 'Møte';
      final date = _meeting!['date'] != null
          ? DateFormat('dd.MM.yyyy').format(DateTime.parse(_meeting!['date']))
          : '';

      // Get all participant emails
      final emails = <String>[];
      for (final p in _participants) {
        final profile = await _sb
            .from('profiles')
            .select('email')
            .eq('id', p['user_id'] as String)
            .maybeSingle();
        final email = profile?['email'] as String?;
        if (email != null && email.isNotEmpty) emails.add(email);
      }

      if (emails.isNotEmpty) {
        final buf = StringBuffer();
        buf.writeln('Hei,');
        buf.writeln();
        buf.writeln('Vedlagt finner du referatet fra møtet "$title" den $date.');
        if (result.comment.isNotEmpty) {
          buf.writeln();
          buf.writeln(result.comment);
        }
        buf.writeln();
        buf.writeln('Mvh');
        buf.writeln('Complete Drums');

        await EmailService.sendEmailWithAttachment(
          to: emails.join(';'),
          subject: 'Referat: $title — $date',
          body: buf.toString(),
          attachmentBytes: pdfBytes,
          attachmentFilename: 'Referat_${title.replaceAll(' ', '_')}.pdf',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Referat sendt!')),
          );
        }
      }
    } catch (e) {
      debugPrint('Send minutes error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved sending: $e')),
        );
      }
    }
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  void _startMeeting() async {
    await MeetingService.updateStatus(widget.meetingId, 'in_progress');
    if (mounted) context.go('/m/meetings/${widget.meetingId}/live');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_meeting == null) {
      return const Center(child: Text('Møte ikke funnet'));
    }

    final title = _meeting!['title'] ?? '';
    final date = _meeting!['date'] != null
        ? DateFormat('dd.MM.yyyy').format(DateTime.parse(_meeting!['date']))
        : '';
    final startTime = _meeting!['start_time'] ?? '';
    final endTime = _meeting!['end_time'] ?? '';
    final address = _meeting!['address'] ?? '';
    final postalCode = _meeting!['postal_code'] ?? '';
    final city = _meeting!['city'] ?? '';
    final comment = _meeting!['comment'] ?? '';
    final status = _meeting!['status'] ?? 'draft';

    final timeStr = [
      if (startTime.isNotEmpty) startTime.toString().substring(0, 5),
      if (endTime.isNotEmpty) '– ${endTime.toString().substring(0, 5)}',
    ].join(' ');

    final locationStr = [address, postalCode, city]
        .where((s) => s.isNotEmpty)
        .join(', ');

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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/m/meetings'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Innkalling sent timestamp
            if (_meeting!['invitation_sent_at'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      'Innkalling sendt ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_meeting!['invitation_sent_at']).toLocal())}',
                      style: const TextStyle(fontSize: 13, color: Colors.green),
                    ),
                  ],
                ),
              ),

            // Action buttons
            Row(
              children: [
                if (status == 'finalized' || status == 'in_progress') ...[
                  FilledButton.icon(
                    onPressed: _sendInvitation,
                    icon: const Icon(Icons.email, size: 18),
                    label: const Text('Send innkalling'),
                  ),
                  const SizedBox(width: 12),
                ],
                // Edit button — always available except when completed
                if (status != 'completed')
                  OutlinedButton.icon(
                    onPressed: () => context.go('/m/meetings/${widget.meetingId}/edit'),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Rediger'),
                  ),
                if (status != 'completed') const SizedBox(width: 12),
                if (status == 'finalized')
                  FilledButton.icon(
                    onPressed: _startMeeting,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start møtet'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700),
                  ),
                if (status == 'in_progress')
                  FilledButton.icon(
                    onPressed: () => context.go('/m/meetings/${widget.meetingId}/live'),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Fortsett møtet'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700),
                  ),
                if (status == 'completed') ...[
                  FilledButton.icon(
                    onPressed: _sendMinutes,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Send referat'),
                  ),
                ],
                const Spacer(),
                // PDF buttons
                if (_invitationPdf != null)
                  _pdfButton('Innkalling', Colors.red, _invitationPdf!),
                const SizedBox(width: 8),
                _pdfButton(
                  'Referat',
                  _minutesPdf != null ? Colors.red : Colors.grey,
                  _minutesPdf,
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Meeting Info section
            _section('Møteinfo'),
            _infoTile(Icons.calendar_today, 'Dato', date),
            if (timeStr.isNotEmpty) _infoTile(Icons.access_time, 'Tid', timeStr),
            if (locationStr.isNotEmpty)
              _infoTile(Icons.location_on, 'Sted', locationStr),
            if (comment.isNotEmpty)
              _infoTile(Icons.comment, 'Kommentar', comment),

            const SizedBox(height: 24),

            // Participants section
            _section('Deltakere'),
            ..._participants.map((p) {
              final name = _userNames[p['user_id']] ?? 'Ukjent';
              final rsvp = p['rsvp_status'] ?? 'pending';
              final rsvpLabel = const {
                'pending': 'Venter',
                'attending': 'Kommer',
                'not_attending': 'Kommer ikke',
              }[rsvp] ?? rsvp;
              final rsvpColor = const {
                'pending': Colors.orange,
                'attending': Colors.green,
                'not_attending': Colors.red,
              }[rsvp] ?? Colors.grey;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: rsvpColor.withOpacity(0.15),
                  child: Icon(Icons.person, color: rsvpColor, size: 20),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: rsvpColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(rsvpLabel,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: rsvpColor)),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Agenda section
            _section('Agenda'),
            ..._agendaItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final itemTitle = item['title'] ?? '';
              final sakNumber = item['sak_number'] as String?;
              final itemType = item['item_type'] ?? 'none';
              final description = item['description'] ?? '';
              final assignedTo = item['assigned_to'] != null
                  ? _userNames[item['assigned_to']] ?? ''
                  : '';
              final notes = item['notes'] ?? '';
              final files = List<Map<String, dynamic>>.from(
                  item['meeting_agenda_files'] ?? []);

              final typeLabel = const {
                'information': 'Informasjonssak',
                'decision': 'Vedtakssak',
                'other': 'Annet',
              }[itemType];

              return Container(
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
                        Text('${sakNumber ?? '${i + 1}'}. $itemTitle',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (typeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(typeLabel,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    if (assignedTo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Ansvarlig: $assignedTo',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Referat:',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green)),
                            const SizedBox(height: 4),
                            Text(notes),
                          ],
                        ),
                      ),
                    ],
                    if (files.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: files.map((f) {
                          final fileName = f['file_name'] ?? 'Fil';
                          final fileUrl = f['file_url'] ?? '';
                          return ActionChip(
                            avatar: const Icon(Icons.attach_file, size: 14),
                            label: Text(fileName, style: const TextStyle(fontSize: 12)),
                            onPressed: () {
                              if (fileUrl.isNotEmpty) {
                                launchUrl(Uri.parse(fileUrl));
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.black54)),
      );

  Widget _infoTile(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black45),
            const SizedBox(width: 10),
            Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _pdfButton(String label, Color color, Uint8List? bytes) {
    return OutlinedButton.icon(
      onPressed: bytes != null
          ? () async {
              // For now just generate and show snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label PDF generert (${bytes.length} bytes)')),
              );
            }
          : null,
      icon: Icon(Icons.picture_as_pdf, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: color.withOpacity(0.5))),
    );
  }
}

// ---------------------------------------------------------------
// SEND DIALOG
// ---------------------------------------------------------------

class _SendDialog extends StatefulWidget {
  final String title;
  final List<String> participantUserIds;
  final Map<String, String> userNames;
  final TextEditingController commentCtrl;

  const _SendDialog({
    required this.title,
    required this.participantUserIds,
    required this.userNames,
    required this.commentCtrl,
  });

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.participantUserIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mottakere:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...widget.participantUserIds.map((uid) {
              final name = widget.userNames[uid] ?? 'Ukjent';
              return CheckboxListTile(
                dense: true,
                value: _selectedIds.contains(uid),
                title: Text(name),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(uid);
                    } else {
                      _selectedIds.remove(uid);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 16),
            const Text('Kommentar:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: widget.commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Valgfri kommentar...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            recipients: _selectedIds.join(','),
            comment: widget.commentCtrl.text,
          )),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
