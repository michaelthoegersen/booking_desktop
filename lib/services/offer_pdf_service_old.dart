import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/offer_draft.dart';
import '../models/app_settings.dart';

// VIKTIG
import 'package:booking_desktop/services/trip_calculator.dart';

class OfferPdfService {
  static const String _termsText = """
1. General Pricing and Additional Costs
Any extra days beyond the agreed travel plan will be invoiced at 13,500 SEK per day, plus 22 SEK per km beyond the offered distance.
In addition to the agreed price, any costs for parking, per diem/diet, and hotel for the driver will be invoiced if overnight stays in the bus 
are not possible.
The price includes: driver, double drivers (if applicable), travel expenses, fuel, road taxes, tolls, and ferries.
Pricing is based on a diesel price of 18 SEK excl. VAT / 22 SEK incl. VAT per liter. If costs for fuel, tolls, ferries, or other transport-related 
fees increase significantly, the difference will be invoiced after the tour.
A VAT rate of 6% will be added to transport services, and 25% to other costs.

2. Electricity Requirements
The bus requires 1 x 400V 32A three-phase power connection upon arrival.

3. Responsibility and Liability
The customer is responsible for ensuring that all equipment is properly packaged and fully insured throughout the assignment.
Coach Service Scandinavia is not financially responsible for delays or cancellations caused by unforeseen events, except for costs related 
to alternative bus transport if the fault can be attributed to us.
All drivers comply with applicable international driving and rest-time regulations.
The customer is responsible for ensuring that the schedule complies with working time regulations.
The customer must ensure that power supply is available to the bus while it is stationary.

4. Booking, Availability, and Replacement
This offer does not constitute a reservation of vehicles or personnel.
Resources are reserved only once we receive an official order.

5. Safety and Behavior
Smoking is strictly prohibited on board our buses.
One initial bed-making is included.

6. Payment Terms
An advance payment of 30% will be invoiced upon ordering.
The remaining balance is invoiced 14 days before the tour.

7. Cancellation Policy
- Less than 60 days: 50%
- Less than 30 days: 100%

8. Validity of the Offer
This offer is valid for 7 days.

9. Acceptance
""";
  // ============================================================
  // BUS IMAGE HELPER
  // ============================================================

  static String _busImageForType(BusType type) {
    switch (type) {
      case BusType.sleeper12:
        return 'assets/pdf/buses/12_sleeper.png';

      case BusType.sleeper14:
        return 'assets/pdf/buses/14_sleeper.png';

      case BusType.sleeper16:
        return 'assets/pdf/buses/16_sleeper.png';

      case BusType.sleeper18:
        return 'assets/pdf/buses/18_sleeper.png';

      case BusType.sleeper12StarRoom:
        return 'assets/pdf/buses/12_sleeper.png';
    }
  }

  // ============================================================
  // MAIN
  // ============================================================

  static Future<Uint8List> buildPdf({
    required OfferDraft offer,
    required AppSettings settings,
    required Map<int, RoundCalcResult> roundCalcByIndex,
  }) async {
    // ------------------------
    // TEMPLATE
    // ------------------------
    final template = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/template_page0.png'))
          .buffer
          .asUint8List(),
    );

    // ------------------------
    // BUS IMAGE
    // ------------------------
    final busPath = _busImageForType(offer.busType);

    final busImage = pw.MemoryImage(
      (await rootBundle.load(busPath)).buffer.asUint8List(),
    );

    // ------------------------
    // FONTS
    // ------------------------
    final calibri = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibri.ttf'),
    );

    final calibriBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibrib.ttf'),
    );

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Stack(
            children: [
              // ==================================================
              // BACKGROUND
              // ==================================================
              pw.Image(template, fit: pw.BoxFit.fill),

              // ==================================================
              // BUS IMAGE (TOP LEFT)
              // ==================================================
              pw.Positioned(
                left: 370,
                top: 70,
                child: pw.Image(
                  busImage,
                  width: 170,
                  fit: pw.BoxFit.contain,
                ),
              ),

              // ==================================================
              // LEFT INFO
              // ==================================================
              _posText(
                left: 423,
                top: 118,
                width: 250,
                text: offer.company,
                font: calibri,
                fontSize: 8,
              ),
              _posText(
                left: 423,
                top: 130,
                width: 250,
                text: offer.contact,
                font: calibri,
                fontSize: 8,
              ),
              _posText(
                left: 423,
                top: 164,
                width: 250,
                text: offer.production,
                font: calibri,
                fontSize: 8,
              ),

              // ==================================================
              // RIGHT INFO
              // ==================================================
              _posText(
                left: 595,
                top: 206,
                width: 180,
                text: offer.company,
                font: calibri,
                fontSize: 10,
              ),
              _posText(
                left: 595,
                top: 248,
                width: 180,
                text: offer.production,
                font: calibri,
                fontSize: 10,
              ),
              _posText(
                left: 595,
                top: 270,
                width: 180,
                text: "${offer.busCount} x ${offer.busType.label}",
                font: calibri,
                fontSize: 10,
              ),
              _posText(
                left: 595,
                top: 292,
                width: 180,
                text: _offerDateSpan(offer),
                font: calibri,
                fontSize: 10,
              ),
              _posText(
                left: 595,
                top: 314,
                width: 180,
                text: _validUntil(),
                font: calibri,
                fontSize: 10,
              ),

              // ==================================================
              // TABLE
              // ==================================================
              _buildTable(
                offer: offer,
                settings: settings,
                roundCalcByIndex: roundCalcByIndex,
                font: calibri,
              ),
              _buildFooter(font: calibri),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ============================================================
  // TABLE
  // ============================================================

  static pw.Widget _buildTable({
    required OfferDraft offer,
    required AppSettings settings,
    required Map<int, RoundCalcResult> roundCalcByIndex,
    required pw.Font font,
  }) {
    const double startY = 263;
    const double rowHeight = 14;

    const double colRound = 95;
    const double colDate = 140;
    const double colCity = 186;
    const double colKm = 235;
    const double colTime = 281;
    const double colExtra = 326;
    const double colRest = 640;
    const double colPrice = 385;

    final widgets = <pw.Widget>[];

    double y = startY;
    int roundNo = 1;

    for (int i = 0; i < offer.rounds.length; i++) {
      final round = offer.rounds[i];

      if (round.entries.isEmpty) continue;

      final calc = roundCalcByIndex[i];

      // ROUND BOX
      final double roundStartY = y;
      final double roundHeight = round.entries.length * rowHeight;

      widgets.add(
        pw.Positioned(
          left: 90,
          top: roundStartY - 4,
          child: pw.Container(
            width: 400,
            height: roundHeight + 15,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: PdfColors.grey700,
                width: 0.7,
              ),
              borderRadius: pw.BorderRadius.circular(4),
            ),
          ),
        ),
      );

      for (int r = 0; r < round.entries.length; r++) {
        final e = round.entries[r];

        final double kmValue =
            (calc != null && r < calc.legKm.length) ? calc.legKm[r] : 0;

        final String legKm =
            kmValue > 0 ? "${kmValue.round()} km" : "";

        final hasDDrive =
            kmValue >= settings.dDriveKmThreshold && kmValue > 0;

        final timeText = _calcTimeText(
          km: kmValue,
          hasDDrive: hasDDrive,
        );

        final priceText = r == 0 ? _formatNok(calc?.totalCost) : "";

        widgets.addAll([
          _cellText(colRound, y, roundNo.toString(), font),

          _cellText(
            colDate,
            y,
            DateFormat("dd.MM.yyyy").format(e.date),
            font,
          ),

          _cellText(colCity, y, e.location, font),

          _cellText(colKm, y, legKm, font),

          _cellText(colTime, y, timeText, font),

          _cellText(
            colExtra,
            y,
            _buildExtraText(
              hasDDrive: hasDDrive,
              extraField: e.extra,
            ),
            font,
          ),

          _cellText(colRest, y, "-", font),

          _cellText(
            colPrice,
            y + 57,
            priceText,
            font,
            right: true,
          ),
        ]);

        y += rowHeight;
      }

      // DAYS
      final days = round.entries.length;

      widgets.add(
        _cellText(colDate, y, "$days days", font),
      );

      // TOTAL KM
      if (calc != null) {
        widgets.add(
          _cellText(
            colKm,
            y,
            "${calc.totalKm.round()} km",
            font,
          ),
        );
      }

      y += rowHeight + 6;

      roundNo++;
    }

    return pw.Stack(children: widgets);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static pw.Widget _cellText(
    double left,
    double top,
    String text,
    pw.Font font, {
    bool right = false,
  }) {
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: 90,
        child: pw.Text(
          text,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            font: font,
            fontSize: 8,
          ),
        ),
      ),
    );
  }

  static pw.Widget _posText({
    required double left,
    required double top,
    required double width,
    required String text,
    required pw.Font font,
    required double fontSize,
  }) {
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: width,
        child: pw.Text(
          text,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            font: font,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TIME CALC
  // ============================================================

  static String _calcTimeText({
    required double km,
    required bool hasDDrive,
  }) {
    if (km <= 0) return "";

    double hours = km / 60.0;

    if (!hasDDrive) {
      if (hours > 9) {
        hours += 1.5;
      } else if (hours > 4.5) {
        hours += 0.75;
      }
    }

    final totalMinutes = (hours * 60).round();

    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    return "${h}h ${m}m";
  }

  // ============================================================
  // DATE / FORMAT
  // ============================================================

  static String _validUntil() {
    final d = DateTime.now().add(const Duration(days: 14));
    return DateFormat("dd.MM.yyyy").format(d);
  }

  static String _offerDateSpan(OfferDraft offer) {
    DateTime? first;
    DateTime? last;

    for (final r in offer.rounds) {
      for (final e in r.entries) {
        first ??= e.date;
        last = e.date;
      }
    }

    if (first == null) return "-";

    return last == null
        ? DateFormat("dd.MM.yyyy").format(first)
        : "${DateFormat("dd.MM.yyyy").format(first)} - "
            "${DateFormat("dd.MM.yyyy").format(last)}";
  }

  static String _formatNok(num? v) {
    if (v == null || v == 0) return "";

    final f = NumberFormat("#,###", "en_US");
    return "kr ${f.format(v)}";
  }

  // ============================================================
  // EXTRA
  // ============================================================

  static String _buildExtraText({
    required bool hasDDrive,
    required String extraField,
  }) {
    final extras = <String>[];

    if (hasDDrive) extras.add("D.Drive");

    final e = extraField.trim();

    if (e.isNotEmpty) {
      final parts = e
          .split(RegExp(r'[/,]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);

      for (final p in parts) {
        final low = p.toLowerCase();

        if (low.contains("ferry")) extras.add("Ferry");
        if (low.contains("bridge")) extras.add("Bridge");
      }
    }

    return extras.isEmpty ? "" : extras.join("/");
  }
  // ============================================================
// FOOTER / TERMS
// ============================================================

static pw.Widget _buildFooter({
  required pw.Font font,
}) {
  return pw.Positioned(
    left: 60,
    top: 400,
    right: 60,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 24),



        pw.Text(
          "Terms and Conditions:",
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),

        pw.SizedBox(height: 6),

        pw.Text(
          _termsText,
          style: pw.TextStyle(
            fontSize: 9,
            height: 1.4,
            font: font,
          ),
        ),

        pw.SizedBox(height: 20),

        pw.Text(
          "Location and date: ____________________________",
          style: pw.TextStyle(fontSize: 9),
        ),

        pw.SizedBox(height: 6),

        pw.Text(
          "Customer name: _______________________________",
          style: pw.TextStyle(fontSize: 9),
        ),

        pw.SizedBox(height: 6),

        pw.Text(
          "Signature: ___________________________________",
          style: pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
}
}