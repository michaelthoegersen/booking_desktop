import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/offer_draft.dart';
import '../models/app_settings.dart';
import 'package:booking_desktop/services/trip_calculator.dart';

class OfferPdfService {
  // ============================================================
  // TERMS
  // ============================================================

  static const String _termsText = """
Terms and Conditions:

1. General Pricing and Additional Costs
Any extra days beyond the agreed travel plan will be invoiced at 13,500 SEK per day, plus 22 SEK per km beyond the offered distance.
In addition to the agreed price, any costs for parking, per diem/diet, and hotel for the driver will be invoiced if overnight stays in the bus are not possible.
The price includes: driver, double drivers (if applicable), travel expenses, fuel, road taxes, tolls, and ferries.
Pricing is based on a diesel price of 18 SEK excl. VAT / 22 SEK incl. VAT per liter. If costs for fuel, tolls, ferries, or other transport-related fees increase significantly, the difference will be invoiced after the tour.
A VAT rate of 6% will be added to transport services, and 25% to other costs.

2. Electricity Requirements
The bus requires 1 x 400V 32A three-phase power connection upon arrival.

3. Responsibility and Liability
The customer is responsible for ensuring that all equipment is properly packaged and fully insured throughout the assignment.
Coach Service Scandinavia is not financially responsible for delays or cancellations caused by unforeseen events, except for costs related to alternative bus transport if the fault can be attributed to us.
All drivers comply with applicable international driving and rest-time regulations.
The customer is responsible for ensuring that the schedule complies with working time regulations.
The customer must ensure that power supply is available to the bus while it is stationary at concerts, shows, festivals, and similar events.

4. Booking, Availability, and Replacement of Vehicles or Personnel
This offer does not constitute a reservation of vehicles or personnel. Resources are reserved only once we receive an official order.
We reserve the right to decline the assignment if it cannot be coordinated with our other commitments.
We reserve the right, in consultation with the client’s representative, to replace vehicles and/or personnel, even during an ongoing assignment, if necessary. Any replacement will be of equal or superior quality to the originally specified resources.

5. Safety, Behavior, and Onboard Facilities
Smoking is strictly prohibited on board our buses. Any cleaning required due to smoking will be invoiced to the customer.
One initial bed-making is included at the start of the journey. If additional bed-making is required during the tour, a fee of 250 SEK per bed will be charged.
According to maritime law, passengers are not permitted to stay inside vehicles during ferry crossings within the European Union. It is the customer's responsibility to inform all passengers accordingly.

6. Payment Terms
An advance payment of 30% of the total net amount will be invoiced upon ordering and must be paid for the booking to be confirmed.
The remaining balance will be invoiced 14 days before the tour starts and must be fully paid before the tour begins.

7. Cancellation Policy
If the customer cancels the assignment:
- Less than 60 days before the first day of the event: 50% of the agreed total amount will be invoiced.
- Less than 30 days before the first day of the event: 100% of the agreed total amount will be invoiced.

8. Validity of the Offer
This offer is valid for 7 days from today’s date and assumes that a vehicle is still available at the time of ordering.

9. Acceptance
""";

  // ============================================================
  // BUS TYPE IMAGE
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
    final doc = pw.Document();

    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibri.ttf'),
    );

    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/calibrib.ttf'),
    );

    final appLogo = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/logos/LOGOapp.png'))
          .buffer
          .asUint8List(),
    );

    final busLayout = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/buses/DDBus.png'))
          .buffer
          .asUint8List(),
    );

    final busTypeImage = pw.MemoryImage(
      (await rootBundle.load(
        _busImageForType(offer.busType),
      ))
          .buffer
          .asUint8List(),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 40),
        build: (context) => [
          _buildTopBar(appLogo, regular),

          pw.SizedBox(height: 20),

          _buildTopContent(
            offer,
            busLayout,
            busTypeImage,
            regular,
          ),

          pw.SizedBox(height: 30),

          _buildOfferTitle(bold),

          pw.SizedBox(height: 15),

          _buildTable(
            offer,
            settings,
            roundCalcByIndex,
            regular,
            bold,
          ),

          pw.SizedBox(height: 30),

          _buildTerms(regular, bold),

          pw.SizedBox(height: 30),

          _buildSignature(regular),
        ],
      ),
    );

    return doc.save();
  }

  // ============================================================
// BLACK BAR (FIXED ALIGNMENT)
// ============================================================

static pw.Widget _buildTopBar(
  pw.ImageProvider logo,
  pw.Font font,
) {
  return pw.Container(
    width: double.infinity,
    height: 110, // Litt mer luft
    color: PdfColors.black,

    child: pw.Stack(
      children: [

        // LOGO (FULL KONTROLL)
        pw.Positioned(
          left: 0,  // → høyre
          top: -25,   // ↓ ned

          child: pw.Image(
            logo,
            height: 180, // 👈 STØRRELSE (endre denne)
            fit: pw.BoxFit.contain,
          ),
        ),

        // TEKST (låst høyre)
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
// WHITE TEXT (TOP BAR HELPER)
// ============================================================

static pw.Widget _whiteText(String text, pw.Font font) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      font: font,
      fontSize: 10,
      color: PdfColors.white,
    ),
  );
}

  // ============================================================
  // TOP CONTENT
  // ============================================================

  static pw.Widget _buildTopContent(
  OfferDraft offer,
  pw.ImageProvider busLayout,
  pw.ImageProvider busTypeImage,
  pw.Font font,
) {
  return pw.Container(
    height: 95, // Nok plass → ingen clipping
    padding: const pw.EdgeInsets.only(top: -25),
    child: pw.Stack(
      children: [

        // Buss
        pw.Positioned(
          left: 0,
          top: -10, // ALDRI negativ
          child: pw.Image(
            busLayout,
            width: 200,
          ),
        ),

        // Høyre info
        pw.Positioned(
          right: 0,
          top: 15, // ALDRI negativ
          child: pw.Container(
            width: 160,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _rightInfo("Company", offer.company, font),
                _rightInfo("Name", offer.contact, font),
                _rightInfo("Phone", "", font),
                _rightInfo("Email", "", font),
                _rightInfo("Production", offer.production, font),
                _rightInfo(
                  "Vehicle",
                  "${offer.busCount} x ${offer.busType.label}",
                  font,
                ),
                _rightInfo("Date", _offerDateSpan(offer), font),
                _rightInfo("Valid until", _validUntil(), font),

                pw.SizedBox(height: 12),

                pw.Image(
                  busTypeImage,
                  width: 140,
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
  // OFFER TITLE
  // ============================================================

  static pw.Widget _buildOfferTitle(pw.Font bold) {
    return pw.Center(
      child: pw.Text(
        "Offer",
        style: pw.TextStyle(font: bold, fontSize: 24),
      ),
    );
  }

  // ============================================================
  // TABLE
  // ============================================================

  static pw.Widget _buildTable(
    OfferDraft offer,
    AppSettings settings,
    Map<int, RoundCalcResult> calc,
    pw.Font regular,
    pw.Font bold,
  ) {
    final headers = [
      "Round",
      "Date",
      "Location",
      "Km",
      "Time",
      "Extra",
      "Price",
    ];

    final rows = <List<String>>[];

    int roundNo = 1;

    for (int i = 0; i < offer.rounds.length; i++) {
      final round = offer.rounds[i];
      final result = calc[i];

      for (int r = 0; r < round.entries.length; r++) {
        final e = round.entries[r];

        final double km =
            (result != null && r < result.legKm.length)
                ? result.legKm[r].toDouble()
                : 0.0;

        final hasDDrive = km >= settings.dDriveKmThreshold;

        rows.add([
          roundNo.toString(),
          DateFormat("dd.MM.yyyy").format(e.date),
          e.location,
          km > 0 ? "${km.round()}" : "",
          _calcTimeText(km: km, hasDDrive: hasDDrive),
          _buildExtraText(hasDDrive: hasDDrive, extraField: e.extra),
          r == 0 ? _formatNok(result?.totalCost) : "",
        ]);
      }

      roundNo++;
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Table.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(font: bold, fontSize: 9),
        cellStyle: pw.TextStyle(font: regular, fontSize: 8),
        border: pw.TableBorder.all(color: PdfColors.grey600),
      ),
    );
  }

  // ============================================================
  // TERMS
  // ============================================================

  static pw.Widget _buildTerms(pw.Font regular, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Paragraph(
        text: _termsText,
        style: pw.TextStyle(
          font: regular,
          fontSize: 9,
          height: 1.4,
        ),
      ),
    );
  }

  // ============================================================
  // SIGNATURE
  // ============================================================

  static pw.Widget _buildSignature(pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Location and date: ____________________________",
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            "Customer name: _______________________________",
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            "Signature: ___________________________________",
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static String _calcTimeText({
    required double km,
    required bool hasDDrive,
  }) {
    if (km <= 0) return "";

    double hours = km / 60;

    if (!hasDDrive) {
      if (hours > 9) hours += 1.5;
      if (hours > 4.5) hours += 0.75;
    }

    final m = (hours * 60).round();

    return "${m ~/ 60}h ${m % 60}m";
  }

  static String _formatNok(num? v) {
    if (v == null || v == 0) return "";
    return "kr ${NumberFormat('#,###').format(v)}";
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

    return "${DateFormat('dd.MM.yyyy').format(first)} - "
        "${DateFormat('dd.MM.yyyy').format(last!)}";
  }

  static String _validUntil() {
    final d = DateTime.now().add(const Duration(days: 7));
    return DateFormat("dd.MM.yyyy").format(d);
  }

  static String _buildExtraText({
    required bool hasDDrive,
    required String extraField,
  }) {
    final extras = <String>[];

    if (hasDDrive) extras.add("D.Drive");

    final parts = extraField
        .split(RegExp(r'[,/]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final p in parts) {
      if (p.toLowerCase().contains("ferry")) extras.add("Ferry");
      if (p.toLowerCase().contains("bridge")) extras.add("Bridge");
    }

    return extras.join("/");
  }
    static pw.Widget _rightInfo(
    String label,
    String value,
    pw.Font font,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              "$label:",
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}