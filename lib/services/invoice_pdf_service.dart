import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice.dart';

class InvoicePdfService {
  // VAT rates (same as offer_pdf_service.dart)
  static const Map<String, double> _vatRates = {
    'DK': 0.25,
    'DE': 0.19,
    'AT': 0.10,
    'PL': 0.08,
    'BE': 0.06,
    'SI': 0.095,
    'HR': 0.25,
    'Other': 0.0,
  };

  // ============================================================
  // MAIN ENTRY
  // ============================================================

  static Future<Uint8List> generatePdf(Invoice invoice) async {
    final doc = pw.Document();

    // Fonts (same as offer PDF)
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibri.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibrib.ttf'),
    );

    // Logo
    final appLogo = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/logos/LOGOapp.png'))
          .buffer
          .asUint8List(),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 40),
        build: (context) => [
          // 1. Black header bar (identical to offer)
          _buildTopBar(appLogo, regular),
          pw.SizedBox(height: 24),

          // 2. FAKTURA title + invoice meta
          _buildInvoiceHeader(invoice, regular, bold),
          pw.SizedBox(height: 16),

          // 3. Client block
          _buildClientBlock(invoice, regular, bold),
          pw.SizedBox(height: 12),

          // 4. Horizontal divider
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 40),
            child: pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          ),
          pw.SizedBox(height: 12),

          // 5. Round summary table
          _buildRoundsTable(invoice, regular, bold),
          pw.SizedBox(height: 16),

          // 6. VAT box
          _buildTotalsSection(invoice, regular, bold),
          pw.SizedBox(height: 20),

          // 7. Payment info
          _buildPaymentInfo(invoice, regular, bold),
        ],
      ),
    );

    return doc.save();
  }

  // ============================================================
  // BLACK HEADER (identical to offer_pdf_service._buildTopBar)
  // ============================================================

  static pw.Widget _buildTopBar(pw.ImageProvider logo, pw.Font font) {
    return pw.Container(
      width: double.infinity,
      height: 110,
      color: PdfColors.black,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            top: -25,
            child: pw.Image(logo, height: 180, fit: pw.BoxFit.contain),
          ),
          pw.Positioned(
            right: -140,
            top: 40,
            child: pw.Container(
              width: 420,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "Coach Service Scandinavia / STARCOACH - Ring Lillgård 1585 62 Linköping, SE",
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    "Michael: +47 948 93 820  sales@coachservicescandinavia.com",
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    "Benny: +46 73-428 19 48  benny.nyberg@starcoach.nu",
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INVOICE HEADER — "FAKTURA" title + number/date/due date
  // ============================================================

  static pw.Widget _buildInvoiceHeader(
    Invoice invoice,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left: large INVOICE title
          pw.Text(
            "INVOICE",
            style: pw.TextStyle(font: bold, fontSize: 28),
          ),

          pw.Spacer(),

          // Right: invoice meta
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _metaRow("Invoice no.", invoice.invoiceNumber, regular, bold),
              pw.SizedBox(height: 4),
              _metaRow(
                "Invoice date",
                _fmtDate(invoice.invoiceDate),
                regular,
                bold,
              ),
              pw.SizedBox(height: 4),
              _metaRow(
                "Due date",
                _fmtDate(invoice.dueDate),
                regular,
                bold,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          "$label:",
          style: pw.TextStyle(font: regular, fontSize: 9),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          value,
          style: pw.TextStyle(font: bold, fontSize: 9),
        ),
      ],
    );
  }

  // ============================================================
  // CLIENT BLOCK
  // ============================================================

  static pw.Widget _buildClientBlock(
    Invoice invoice,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (invoice.company.isNotEmpty)
            pw.Text(
              invoice.company,
              style: pw.TextStyle(font: bold, fontSize: 11),
            ),
          if (invoice.contact.isNotEmpty)
            pw.Text(
              invoice.contact,
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          if (invoice.phone.isNotEmpty)
            pw.Text(
              invoice.phone,
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          if (invoice.email.isNotEmpty)
            pw.Text(
              invoice.email,
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          if (invoice.production.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              "Production: ${invoice.production}",
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // ROUND SUMMARY TABLE — one row per round
  // ============================================================

  static pw.Widget _buildRoundsTable(
    Invoice invoice,
    pw.Font regular,
    pw.Font bold,
  ) {
    final headers = ["", "Period", "Amount"];

    final rows = invoice.rounds.map((r) {
      final period = "${_fmtDate(r.startDate)} – ${_fmtDate(r.endDate)}";
      return [r.label, period, _formatNok(r.totalCost)];
    }).toList();

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Table.fromTextArray(
        headers: headers,
        data: rows,
        columnWidths: const {
          0: pw.FlexColumnWidth(1.2),
          1: pw.FlexColumnWidth(2.5),
          2: pw.FlexColumnWidth(1.3),
        },
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerRight,
        },
        headerStyle: pw.TextStyle(font: bold, fontSize: 9),
        cellStyle: pw.TextStyle(font: regular, fontSize: 9),
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey400),
          top: pw.BorderSide(color: PdfColors.grey600),
          bottom: pw.BorderSide(color: PdfColors.grey600),
        ),
      ),
    );
  }

  // ============================================================
  // TOTALS SECTION (right-aligned VAT box)
  // ============================================================

  static pw.Widget _buildTotalsSection(
    Invoice invoice,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Container(
            width: 260,
            child: _buildVatBox(
              invoice.vatBreakdown,
              invoice.totalExclVat,
              invoice.totalInclVat,
              regular,
              bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VAT BOX (identical to offer_pdf_service._buildVatBox)
  // ============================================================

  static pw.Widget _buildVatBox(
    Map<String, double> vatMap,
    double excl,
    double incl,
    pw.Font regular,
    pw.Font bold,
  ) {
    const double labelWidth = 120;
    const double valueWidth = 90;

    pw.Widget row(
      String label,
      String value, {
      bool boldText = false,
      bool italic = false,
    }) {
      final style = pw.TextStyle(
        font: boldText ? bold : regular,
        fontSize: 9,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      );

      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text(label, style: style, textAlign: pw.TextAlign.right),
          ),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: valueWidth,
            child: pw.Text(value, style: style, textAlign: pw.TextAlign.right),
          ),
        ],
      );
    }

    final rows = <pw.Widget>[];

    rows.add(row("Total excl. VAT", _formatNok(excl), boldText: true));

    vatMap.forEach((country, value) {
      final rate = ((_vatRates[country] ?? 0) * 100).round();
      rows.add(row("VAT $country $rate%", _formatNok(value), italic: true));
    });

    rows.add(pw.SizedBox(height: 4));

    rows.add(
      pw.Container(
        width: labelWidth + valueWidth + 6,
        height: 0.5,
        color: PdfColors.grey,
      ),
    );

    rows.add(pw.SizedBox(height: 4));

    rows.add(row("Total incl. VAT", _formatNok(incl), boldText: true));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: rows,
    );
  }

  // ============================================================
  // PAYMENT INFO BLOCK
  // ============================================================

  static pw.Widget _buildPaymentInfo(
    Invoice invoice,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "Payment details",
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
            pw.SizedBox(height: 6),
            if (invoice.bankAccount.isNotEmpty)
              pw.Text(
                "Bank account:  ${invoice.bankAccount}",
                style: pw.TextStyle(font: regular, fontSize: 9),
              ),
            if (invoice.paymentRef.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                "Reference:  ${invoice.paymentRef}",
                style: pw.TextStyle(font: regular, fontSize: 9),
              ),
            ],
            pw.SizedBox(height: 3),
            pw.Text(
              "Due date:  ${_fmtDate(invoice.dueDate)}",
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static String _fmtDate(DateTime d) =>
      DateFormat("dd.MM.yyyy").format(d);

  static String _formatNok(num v) =>
      "kr ${NumberFormat('#,###').format(v)}";
}
