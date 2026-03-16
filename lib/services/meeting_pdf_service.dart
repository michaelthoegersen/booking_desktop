import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class MeetingPdfService {
  static final _dateFmt = DateFormat('dd.MM.yyyy');

  // --------------------------------------------------------------------------
  // INNKALLING PDF
  // --------------------------------------------------------------------------

  static Future<Uint8List> generateInvitation({
    required Map<String, dynamic> meeting,
    required List<Map<String, dynamic>> participants,
    required List<Map<String, dynamic>> agendaItems,
    required Map<String, String> userNames, // userId -> name
  }) async {
    final pdf = pw.Document();

    final fonts = await _loadFonts();
    final regularFont = fonts.$1;
    final boldFont = fonts.$2;

    final title = meeting['title'] ?? '';
    final date = meeting['date'] != null ? _dateFmt.format(DateTime.parse(meeting['date'])) : '';
    final startTime = meeting['start_time'] ?? '';
    final endTime = meeting['end_time'] ?? '';
    final address = meeting['address'] ?? '';
    final postalCode = meeting['postal_code'] ?? '';
    final city = meeting['city'] ?? '';
    final comment = meeting['comment'] ?? '';

    final timeStr = [
      if (startTime.isNotEmpty) startTime.substring(0, 5),
      if (endTime.isNotEmpty) '- ${endTime.substring(0, 5)}',
    ].join(' ');

    final locationStr = [
      if (address.isNotEmpty) address,
      if (postalCode.isNotEmpty || city.isNotEmpty)
        [postalCode, city].where((s) => s.isNotEmpty).join(' '),
    ].join(', ');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (ctx) => [
          // Header
          pw.Text('INNKALLING TIL MØTE',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),

          // Meeting info
          _infoRow('Tittel:', title, boldFont, regularFont),
          _infoRow('Dato:', date, boldFont, regularFont),
          if (timeStr.isNotEmpty) _infoRow('Tid:', timeStr, boldFont, regularFont),
          if (locationStr.isNotEmpty) _infoRow('Sted:', locationStr, boldFont, regularFont),
          if (comment.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _infoRow('Kommentar:', comment, boldFont, regularFont),
          ],

          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 12),

          // Participants
          pw.Text('DELTAKERE',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ...participants.map((p) {
            final name = userNames[p['user_id']] ?? 'Ukjent';
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text('- $name', style: const pw.TextStyle(fontSize: 11)),
            );
          }),

          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 12),

          // Agenda
          pw.Text('AGENDA',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),

          ...agendaItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final itemTitle = item['title'] ?? '';
            final itemType = item['item_type'] ?? 'none';
            final description = item['description'] ?? '';
            final assignedTo = item['assigned_to'] != null
                ? userNames[item['assigned_to']] ?? ''
                : '';

            final typeLabel = const {
              'information': 'Informasjon',
              'decision': 'Beslutning',
              'other': 'Annet',
            }[itemType];

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Text('${i + 1}. ',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(itemTitle,
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ),
                    if (typeLabel != null)
                      pw.Text('[$typeLabel]',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ]),
                  if (assignedTo.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20, top: 2),
                      child: pw.Text('Ansvarlig: $assignedTo',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    ),
                  if (description.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20, top: 4),
                      child: pw.Text(description, style: const pw.TextStyle(fontSize: 11)),
                    ),
                  // Files
                  if (item['meeting_agenda_files'] != null)
                    ...((item['meeting_agenda_files'] as List).map((f) =>
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 20, top: 2),
                        child: pw.Text('[Fil] ${f['file_name']}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue)),
                      ),
                    )),
                ],
              ),
            );
          }),
        ],
      ),
    );

    return pdf.save();
  }

  // --------------------------------------------------------------------------
  // REFERAT PDF
  // --------------------------------------------------------------------------

  static Future<Uint8List> generateMinutes({
    required Map<String, dynamic> meeting,
    required List<Map<String, dynamic>> participants,
    required List<Map<String, dynamic>> agendaItems,
    required Map<String, String> userNames,
  }) async {
    final pdf = pw.Document();

    final fonts = await _loadFonts();
    final regularFont = fonts.$1;
    final boldFont = fonts.$2;

    final title = meeting['title'] ?? '';
    final date = meeting['date'] != null ? _dateFmt.format(DateTime.parse(meeting['date'])) : '';
    final startTime = meeting['start_time'] ?? '';
    final endTime = meeting['end_time'] ?? '';

    final timeStr = [
      if (startTime.isNotEmpty) startTime.substring(0, 5),
      if (endTime.isNotEmpty) '- ${endTime.substring(0, 5)}',
    ].join(' ');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (ctx) => [
          pw.Text('MØTEREFERAT',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),

          _infoRow('Møte:', title, boldFont, regularFont),
          _infoRow('Dato:', date, boldFont, regularFont),
          if (timeStr.isNotEmpty) _infoRow('Tid:', timeStr, boldFont, regularFont),

          pw.SizedBox(height: 12),
          pw.Text('Tilstede:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          ...participants
              .where((p) => p['rsvp_status'] == 'attending')
              .map((p) => pw.Text('• ${userNames[p['user_id']] ?? 'Ukjent'}',
                  style: const pw.TextStyle(fontSize: 11))),

          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 12),

          ...agendaItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final itemTitle = item['title'] ?? '';
            final itemType = item['item_type'] ?? 'none';
            final notes = item['notes'] ?? '';
            final assignedTo = item['assigned_to'] != null
                ? userNames[item['assigned_to']] ?? ''
                : '';

            final typeLabel = const {
              'information': 'Informasjon',
              'decision': 'Beslutning',
              'other': 'Annet',
            }[itemType];

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Text('${i + 1}. ',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(itemTitle,
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ),
                    if (typeLabel != null)
                      pw.Text('[$typeLabel]',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ]),
                  if (assignedTo.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20, top: 2),
                      child: pw.Text('Ansvarlig: $assignedTo',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    ),
                  if (notes.isNotEmpty)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(left: 20, top: 6),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(notes, style: const pw.TextStyle(fontSize: 11)),
                    )
                  else
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20, top: 4),
                      child: pw.Text('(Ingen referat)',
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500,
                              fontStyle: pw.FontStyle.italic)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );

    return pdf.save();
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------

  static pw.Widget _infoRow(String label, String value, pw.Font boldFont, pw.Font regularFont) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(label,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static Future<(pw.Font, pw.Font)> _loadFonts() async {
    Future<Uint8List> loadAssetBytes(String path) async {
      final data = await rootBundle.load(path);
      return Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }

    pw.Font regularFont;
    pw.Font boldFont;
    if (kIsWeb) {
      regularFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    } else {
      try {
        regularFont = pw.Font.ttf(ByteData.view(
            (await loadAssetBytes('assets/fonts/Calibri.ttf')).buffer));
        boldFont = pw.Font.ttf(ByteData.view(
            (await loadAssetBytes('assets/fonts/CalibriBold.ttf')).buffer));
      } catch (_) {
        regularFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }
    }
    return (regularFont, boldFont);
  }
}
