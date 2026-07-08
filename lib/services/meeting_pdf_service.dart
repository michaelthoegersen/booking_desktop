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
    List<Map<String, dynamic>> signatures = const [],
  }) async {
    final pdf = pw.Document();

    final fonts = await _loadFonts();
    final regularFont = fonts.$1;
    final boldFont = fonts.$2;

    // Load logo
    pw.ImageProvider? logo;
    try {
      final data = await rootBundle.load('assets/pdf/logos/CompleteDrumsWhite.png');
      logo = pw.MemoryImage(Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
    } catch (_) {}

    final title = meeting['title'] ?? '';
    final date = meeting['date'] != null ? _dateFmt.format(DateTime.parse(meeting['date'])) : '';
    final startTime = meeting['start_time'] ?? '';
    final endTime = meeting['end_time'] ?? '';
    final address = meeting['address'] ?? '';
    final city = meeting['city'] ?? '';
    final location = [address, city].where((s) => s.isNotEmpty).join(', ');

    final timeStr = [
      if (startTime.isNotEmpty) startTime.toString().substring(0, 5),
      if (endTime.isNotEmpty) '- ${endTime.toString().substring(0, 5)}',
    ].join(' ');

    final attending = participants
        .where((p) => p['rsvp_status'] == 'attending')
        .map((p) => userNames[p['user_id']] ?? 'Ukjent')
        .toList();

    final todayStr = _dateFmt.format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Side ${ctx.pageNumber} av ${ctx.pagesCount}',
            style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        build: (ctx) => [
          // ── BLACK HEADER WITH LOGO ──
          if (logo != null)
            pw.Container(
              margin: const pw.EdgeInsets.only(left: -40, right: -40, top: -40),
              width: double.infinity,
              height: 70,
              color: PdfColors.black,
              child: pw.Stack(children: [
                pw.Positioned(
                  left: 12, top: 0, bottom: 0,
                  child: pw.Center(child: pw.Image(logo, height: 55, fit: pw.BoxFit.contain)),
                ),
                pw.Positioned(
                  right: 16, top: 0, bottom: 0,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('MØTEREFERAT', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.white, letterSpacing: 2)),
                      pw.SizedBox(height: 2),
                      pw.Text(todayStr, style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey400)),
                    ],
                  ),
                ),
              ]),
            )
          else
            pw.Text('MØTEREFERAT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),

          pw.SizedBox(height: 24),

          // ── MEETING INFO TABLE ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 14)),
                pw.SizedBox(height: 8),
                pw.Row(children: [
                  _metaLabel('Dato', boldFont), pw.Text(date, style: pw.TextStyle(font: regularFont, fontSize: 10)),
                  pw.SizedBox(width: 24),
                  if (timeStr.isNotEmpty) ...[
                    _metaLabel('Tid', boldFont), pw.Text(timeStr, style: pw.TextStyle(font: regularFont, fontSize: 10)),
                  ],
                ]),
                if (location.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    _metaLabel('Sted', boldFont), pw.Text(location, style: pw.TextStyle(font: regularFont, fontSize: 10)),
                  ]),
                ],
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // ── AGENDA ITEMS WITH NOTES ──
          ...agendaItems.asMap().entries.expand((entry) {
            final i = entry.key;
            final item = entry.value;
            final itemTitle = item['title'] ?? '';
            final itemType = item['item_type'] ?? 'none';
            final notes = item['notes'] ?? '';
            final description = item['description'] ?? '';
            final assignedTo = item['assigned_to'] != null
                ? userNames[item['assigned_to']] ?? ''
                : '';

            final typeLabel = const {
              'information': 'Orientering',
              'decision': 'Vedtak',
              'other': 'Annet',
            }[itemType];

            // Return flat list of widgets — MultiPage handles page breaks between them
            return <pw.Widget>[
              if (i > 0) pw.SizedBox(height: 16),
              pw.Text(
                '${i + 1}. $itemTitle${typeLabel != null ? '  [$typeLabel]' : ''}',
                style: pw.TextStyle(font: boldFont, fontSize: 12),
              ),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              if (assignedTo.isNotEmpty)
                pw.Text('Ansvarlig: $assignedTo',
                    style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey600)),
              if (description.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(description,
                      style: pw.TextStyle(font: regularFont, fontSize: 10, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic)),
                ),
              pw.SizedBox(height: 6),
              // Split notes into paragraphs so MultiPage can break between them
              if (notes.isEmpty)
                pw.Text('Ingen referat', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey400, fontStyle: pw.FontStyle.italic)),
              ...(notes as String).split('\n').where((String p) => p.trim().isNotEmpty).map((String paragraph) =>
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(paragraph.trim(), style: pw.TextStyle(font: regularFont, fontSize: 10, lineSpacing: 1.5)),
                ),
              ),
            ];
          }),

          // ── SIGNATURES ──
          if (signatures.isNotEmpty) ...[
            pw.SizedBox(height: 30),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 16),
            pw.Text('SIGNATURER', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey700, letterSpacing: 1)),
            pw.SizedBox(height: 12),
            ...signatures.map((sig) {
              final name = sig['signed_name'] as String? ?? userNames[sig['user_id'] as String? ?? ''] ?? 'Ukjent';
              final signedAt = sig['signed_at'] != null
                  ? _dateFmt.format(DateTime.parse(sig['signed_at'].toString()).toLocal())
                  : '';
              final signed = sig['status'] == 'signed';
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (signed) ...[
                      pw.Text(name, style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.blue900)),
                      pw.SizedBox(height: 2),
                      pw.Container(height: 0.5, color: PdfColors.black),
                      pw.SizedBox(height: 3),
                      pw.Text('$name  ·  Dato: $signedAt', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey600)),
                    ] else ...[
                      pw.SizedBox(height: 20),
                      pw.Container(height: 0.5, color: PdfColors.black),
                      pw.SizedBox(height: 3),
                      pw.Text('${userNames[sig['user_id'] as String? ?? ''] ?? 'Ukjent'}  ·  Venter på signatur', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey500)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------

  static pw.Widget _metaLabel(String label, pw.Font boldFont) {
    return pw.Container(
      width: 40,
      child: pw.Text('$label:', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey700)),
    );
  }

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
