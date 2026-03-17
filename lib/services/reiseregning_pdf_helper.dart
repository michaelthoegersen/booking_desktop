import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a reiseregning (travel expense) PDF for ebilag submission.
class ReiseregningPdfHelper {
  static Future<Uint8List> generatePdf({
    required String employeeName,
    required double amount,
    required String vendor,
    required String? receiptDate,
    required String description,
    String? receiptImageUrl,
  }) async {
    final pdf = pw.Document();
    final fmt = DateFormat('dd.MM.yyyy');
    final now = DateTime.now();

    // Try to download receipt image
    pw.MemoryImage? receiptImage;
    if (receiptImageUrl != null && receiptImageUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(receiptImageUrl));
        if (response.statusCode == 200) {
          receiptImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint('Failed to download receipt image for PDF: $e');
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Text(
            'Reiseregning / Utleggsrapport',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generert: ${fmt.format(now)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(),
          pw.SizedBox(height: 16),
          _row('Ansatt', employeeName),
          _row('Dato for utlegg', receiptDate ?? ''),
          if (vendor.isNotEmpty) _row('Leverandør', vendor),
          if (description.isNotEmpty) _row('Beskrivelse', description),
          pw.SizedBox(height: 8),
          _row(
            'Beløp',
            '${NumberFormat('#,##0.00', 'nb_NO').format(amount)} kr',
            bold: true,
          ),
          pw.SizedBox(height: 24),
          pw.Divider(),
          pw.SizedBox(height: 16),
          pw.Text(
            'Kvittering',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (receiptImage != null)
            pw.Center(
              child: pw.Image(receiptImage, width: 400, fit: pw.BoxFit.contain),
            )
          else
            pw.Text(
              'Ingen kvittering vedlagt',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _row(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: bold ? 14 : 12,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
