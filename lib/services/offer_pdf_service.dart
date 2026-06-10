import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/offer_draft.dart';
import '../models/company_branding.dart';
import '../state/settings_store.dart';
import '../state/active_company.dart';
import '../localization/s.dart';
import 'package:tourflow/services/trip_calculator.dart';
import '../models/round_calc_result.dart';
import 'branding_service.dart';

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

static String _busImageForType(String type) {
  if (type.contains('18')) {
    return 'assets/pdf/buses/18_sleeper.png';
  } else if (type.contains('16')) {
    return 'assets/pdf/buses/16_sleeper.png';
  } else if (type.contains('14')) {
    return 'assets/pdf/buses/14_sleeper.png';
  } else {
    return 'assets/pdf/buses/12_sleeper.png';
  }
}

// ============================================================
// MAIN ENTRY
// ============================================================

static Future<Uint8List> generatePdf(
  OfferDraft offer,
  Map<int, RoundCalcResult> roundCalc, {
  String? customerSignature,
  String? customerSignatureDate,
  String? companySignature,
  String? companySignatureDate,
  CompanyBranding? branding,
}) async {
  return buildPdf(
    offer: offer,
    roundCalcByIndex: roundCalc,
    customerSignature: customerSignature,
    customerSignatureDate: customerSignatureDate,
    companySignature: companySignature,
    companySignatureDate: companySignatureDate,
    branding: branding,
  );
}

// ============================================================
// TABLE BUILDER FOR PAGE (FLERE RUNDER, ÉN TOTAL)
// ============================================================

static List<pw.Widget> _buildTableForIndexes(
  OfferDraft offer,
  Map<int, RoundCalcResult> calc,
  List<int> visibleRounds,
  pw.Font regular,
  pw.Font bold, {
  bool showGrandTotal = false,
}) {
  final widgets = <pw.Widget>[];

  double grandTotal = 0;
  double grandFerry = 0;
  double grandBridge = 0;
  double grandToll = 0;
  final Map<String, double> allCountryKm = {};

  // ================= ROUNDS =================
  for (final roundIndex in visibleRounds) {
    final round = offer.rounds[roundIndex];
    final result = calc[roundIndex];

    if (round.entries.isEmpty || result == null) continue;

    // ---- totalsamling (manual override takes priority)
    final roundPrice = offer.roundOverrides[roundIndex] ?? result.totalCost;
    if (roundPrice != null) {
      grandTotal += roundPrice;
    }
    grandFerry += result.ferryCost;
    grandBridge += result.bridgeCost;
    grandToll += result.tollCost;

    for (final entry in round.entries) {
      entry.countryKm.forEach((country, km) {
        if (km <= 0) return;
        allCountryKm[country] =
            (allCountryKm[country] ?? 0) + km;
      });
    }

    // ---- bygg EN runde (samme spacing/design som før)
    widgets.addAll(
      _buildTable(
        offer.copyWithRounds([roundIndex]),
        {0: result},
        regular,
        bold,
        roundNumberOverride: roundIndex + 1,
        subtotalOverride: offer.roundOverrides[roundIndex],
      ),
    );
  }

  // ================= GRAND TOTAL (KUN ÉN GANG) =================
  // totalOverride overrides everything if set
  if (offer.totalOverride != null) grandTotal = offer.totalOverride!;

  if (showGrandTotal && grandTotal > 0) {
    // VAT base = total excluding ferry, bridge and toll (same as new_offer_page)
    final vatBase = grandTotal - grandFerry - grandBridge - grandToll;

    // Total driven km from all rounds (not just country-attributed km)
    double allDrivenKm = 0;
    for (final roundIndex in visibleRounds) {
      final result = calc[roundIndex];
      if (result != null) {
        allDrivenKm += result.legKm.fold<double>(0, (a, b) => a + b);
      }
    }

    final vatMap = _calculateForeignVat(
      basePrice: vatBase,
      countryKm: allCountryKm,
      totalDrivenKm: allDrivenKm,
      totalExVat: grandTotal,
    );

    // grandTotal is excl VAT. Foreign VAT is added on top.
    final vatAdded = vatMap.values.fold(0.0, (a, b) => a + b);
    final totalExVat  = grandTotal;                 // excl VAT
    final totalIncVat = grandTotal + vatAdded;      // incl foreign VAT

    widgets.add(
  pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 40),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260, // 🔒 FAST BREDDE – NØKKELEN
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),

              pw.Text(
                S.t('total', lang: offer.language).toUpperCase(),
                style: pw.TextStyle(font: bold, fontSize: 12),
              ),

              pw.SizedBox(height: 6),

              _buildVatBox(
                vatMap,
                totalExVat,
                totalIncVat,
                regular,
                bold,
                language: offer.language,
              ),

              // 🔒 Gir lik høyde også uten VAT
              pw.SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ),
  ),
);
}

  return widgets;
}

// ============================================================
// REAL PDF BUILDER
// ============================================================

static Future<Uint8List> buildPdf({
  required OfferDraft offer,
  required Map<int, RoundCalcResult> roundCalcByIndex,
  String? customerSignature,
  String? customerSignatureDate,
  String? companySignature,
  String? companySignatureDate,
  CompanyBranding? branding,
}) async {
  final doc = pw.Document();

  // rootBundle.load() on web returns a ByteData that is a *view* into a
  // larger JS ArrayBuffer with a non-zero byteOffset.  The pdf package's
  // TtfParser calls bytes.buffer.asUint8List(absoluteOffset, n) using
  // offsets that assume the font data starts at position 0 in the buffer.
  // ByteData(n) is the only constructor guaranteed to produce a fresh
  // ByteData with offsetInBytes==0 backed by its own ArrayBuffer of
  // exactly n bytes.
  ByteData _safeByteData(ByteData d) {
    final fresh = ByteData(d.lengthInBytes);
    final src = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    fresh.buffer.asUint8List().setAll(0, src);
    debugPrint('pdf font loaded: offset=${fresh.offsetInBytes} len=${fresh.lengthInBytes}');
    return fresh;
  }
  Uint8List _safeBytes(ByteData d) {
    final src = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    final copy = Uint8List(src.length);
    copy.setAll(0, src);
    return copy;
  }

  // ---------------- FONTS ----------------
  final regular = pw.Font.ttf(
    _safeByteData(await rootBundle.load('assets/fonts/calibri.ttf')),
  );
  final bold = pw.Font.ttf(
    _safeByteData(await rootBundle.load('assets/fonts/calibrib.ttf')),
  );

  // ---------------- IMAGES ----------------
  // Use branding logo if available, otherwise fall back to default
  pw.ImageProvider? brandLogo;
  if (branding?.logoUrl != null && branding!.logoUrl!.isNotEmpty) {
    try {
      final logoBytes = await BrandingService.downloadLogoBytes(branding.logoUrl!);
      if (logoBytes != null) brandLogo = pw.MemoryImage(logoBytes);
    } catch (_) {}
  }
  final appLogo = brandLogo ?? pw.MemoryImage(
    _safeBytes(await rootBundle.load('assets/pdf/logos/LOGOapp.png')),
  );

  // Bus images only for CSS (no custom branding = CSS fallback)
  final hasBusImages = brandLogo == null;
  pw.ImageProvider? busLayout;
  pw.ImageProvider? busTypeImage;
  if (hasBusImages) {
    try {
      busLayout = pw.MemoryImage(
        _safeBytes(await rootBundle.load('assets/pdf/buses/DDBus.png')),
      );
      busTypeImage = pw.MemoryImage(
        _safeBytes(await rootBundle.load(_busImageForType(offer.busType))),
      );
    } catch (_) {}
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 40),

      build: (context) => [

        // ---------- HEADER (KUN ÉN GANG)
        _buildTopBar(appLogo, regular, branding: branding),
        pw.SizedBox(height: 20),
        if (busLayout != null && busTypeImage != null)
          _buildTopContent(
            offer,
            busLayout,
            busTypeImage,
            regular,
          )
        else
          _buildTopContentSimple(offer, regular),
        pw.SizedBox(height: 30),
        _buildOfferTitle(bold, language: offer.language),
        pw.SizedBox(height: 15),

        // ---------- ALLE RUNDER (FLYTENDE)
        ..._buildTableForIndexes(
          offer,
          roundCalcByIndex,
          List.generate(offer.rounds.length, (i) => i),
          regular,
          bold,
          showGrandTotal: true, // 👈 TOTAL KOMMER HER
        ),

        // ---------- TERMS + SIGNATURE (RETT ETTER TOTAL)
        pw.SizedBox(height: 30),
        _buildTerms(regular, bold, branding: branding, language: offer.language),
        pw.SizedBox(height: 30),
        _buildSignature(
          regular,
          bold,
          offer.company,
          customerSignature: customerSignature,
          customerSignatureDate: customerSignatureDate,
          companySignature: companySignature,
          companySignatureDate: companySignatureDate,
          branding: branding,
          language: offer.language,
        ),
      ],
    ),
  );

  return doc.save();
}

static List<pw.Widget> _buildSingleRound({
  required int roundIndex,
  required OfferRound round,
  required RoundCalcResult result,
  required pw.Font regular,
  required pw.Font bold,
  String language = 'no',
}) {
  final widgets = <pw.Widget>[];

  widgets.add(
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Text(
        "${S.t('round', lang: language)} ${roundIndex + 1}",
        style: pw.TextStyle(font: bold, fontSize: 12),
      ),
    ),
  );

  widgets.add(pw.SizedBox(height: 8));

  // 👉 HER bruker du eksisterende tabell-logikk
  widgets.addAll(
    _buildTable(
      OfferDraft(language: language)..rounds.add(round),
      {0: result},
      regular,
      bold,
    ),
  );

  widgets.add(
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          "${S.t('pdfSubtotal', lang: language)}: ${_formatNok(result.totalCost)}",
          style: pw.TextStyle(font: bold, fontSize: 9),
        ),
      ),
    ),
  );

  widgets.add(pw.SizedBox(height: 25)); // 🔑 FAST SPACING

  return widgets;
}

static List<pw.Widget> _buildTotalSection({
  required double grandTotal,
  required Map<String, double> countryKm,
  required pw.Font regular,
  required pw.Font bold,
  double? totalDrivenKm,
  String language = 'no',
}) {
  if (grandTotal <= 0) return [];

  final vatMap = _calculateForeignVat(
    basePrice: grandTotal,
    countryKm: countryKm,
    totalDrivenKm: totalDrivenKm,
    totalExVat: grandTotal,
  );

  // grandTotal is excl VAT. Foreign VAT is added on top.
  final vatAdded = vatMap.values.fold(0.0, (a, b) => a + b);
  final totalExVat  = grandTotal;                 // excl VAT
  final totalIncVat = grandTotal + vatAdded;      // incl foreign VAT

  return [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text(
            S.t('total', lang: language).toUpperCase(),
            style: pw.TextStyle(font: bold, fontSize: 12),
          ),
          pw.SizedBox(height: 6),
          _buildVatBox(
            vatMap,
            totalExVat,
            totalIncVat,
            regular,
            bold,
            language: language,
          ),
          pw.SizedBox(height: 20),
        ],
      ),
    ),
  ];
}
  // ============================================================
  // MAIN
  // ============================================================

  // ============================================================
// BLACK BAR (FIXED ALIGNMENT)
// ============================================================

static pw.Widget _buildTopBar(
  pw.ImageProvider logo,
  pw.Font font, {
  CompanyBranding? branding,
}) {
  final bool isBrandedLogo = branding?.logoUrl != null && branding!.logoUrl!.isNotEmpty;
  return pw.Container(
    width: double.infinity,
    height: 110,
    color: PdfColors.black,

    child: pw.Stack(
      children: [

        // LOGO — CSS uses oversized logo with offset, others use contained logo
        if (!isBrandedLogo)
          pw.Positioned(
            left: 0,
            top: -25,
            child: pw.Image(
              logo,
              height: 180,
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: pw.Center(
              child: pw.Image(
                logo,
                height: 50,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),

        // TEKST (låst høyre — same position as CSS original)
        pw.Positioned(
          right: isBrandedLogo ? 20 : -140,
          top: 40,
          child: pw.Container(
            width: isBrandedLogo ? 200 : 420,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  branding?.companyName ?? '',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.white,
                  ),
                ),
                if ((branding?.addressLine ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    branding!.addressLine!,
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white),
                  ),
                ],
                if ((branding?.contactLine1 ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    branding!.contactLine1!,
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white),
                  ),
                ],
                if ((branding?.contactLine2 ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    branding!.contactLine2!,
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white),
                  ),
                ],
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
  for (var i = 0; i < offer.rounds.length; i++) {
  print("PDF ROUND $i trailer = ${offer.rounds[i].trailer}");
}
  // ✅ LEGG HER (FØR return)
  final hasTrailer =
      offer.rounds.any((r) => r.trailer);

  final vehicle =
      "${offer.busCount} x ${offer.busType}"
      "${hasTrailer ? " + trailer" : ""}";
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
                _rightInfo(S.t('company', lang: offer.language), offer.company, font),
_rightInfo(S.t('name', lang: offer.language), offer.contact, font),
_rightInfo(S.t('phone', lang: offer.language), offer.phone ?? "", font),
_rightInfo(S.t('email', lang: offer.language), offer.email ?? "", font),
_rightInfo(S.t('production', lang: offer.language), offer.production, font),
                _rightInfo(
  S.t('vehicle', lang: offer.language),
  vehicle,
  font,
),
                _rightInfo(S.t('date', lang: offer.language), _todayDate(), font),
                _rightInfo(S.t('pdfValidUntil', lang: offer.language), _validUntil(), font),

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

  /// Top content for non-bus companies — same layout as original, all info on right
  static pw.Widget _buildTopContentSimple(OfferDraft offer, pw.Font font) {
    // For trucks the per-round flag means "mellomlagring", not a trailer, so it
    // must not be appended to the vehicle description.
    final isTruck = offer.busType.toLowerCase().contains('lastebil');
    final hasTrailer = offer.rounds.any((r) => r.trailer);
    final vehicle =
        "${offer.busCount} x ${offer.busType}"
        "${hasTrailer && !isTruck ? " + trailer" : ""}";
    return pw.Container(
      height: 95,
      padding: const pw.EdgeInsets.only(top: -25),
      child: pw.Stack(
        children: [
          // All info on the right — same position as original
          pw.Positioned(
            right: 0,
            top: 15,
            child: pw.Container(
              width: 160,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _rightInfo(S.t('company', lang: offer.language), offer.company, font),
                  _rightInfo(S.t('name', lang: offer.language), offer.contact, font),
                  _rightInfo(S.t('phone', lang: offer.language), offer.phone ?? "", font),
                  _rightInfo(S.t('email', lang: offer.language), offer.email ?? "", font),
                  _rightInfo(S.t('production', lang: offer.language), offer.production, font),
                  _rightInfo(S.t('vehicle', lang: offer.language), vehicle, font),
                  _rightInfo(S.t('date', lang: offer.language), _todayDate(), font),
                  _rightInfo(S.t('pdfValidUntil', lang: offer.language), _validUntil(), font),
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

static pw.Widget _buildOfferTitle(pw.Font bold, {String language = 'no'}) {
  return pw.Center(
    child: pw.Text(
      S.t('offerPdfTitle', lang: language),
      style: pw.TextStyle(
        font: bold,
        fontSize: 24,
      ),
    ),
  );
}
  static List<pw.Widget> _buildTable(
  OfferDraft offer,
  Map<int, RoundCalcResult> calc,
  pw.Font regular,
  pw.Font bold, {
  int? roundNumberOverride,
  double? subtotalOverride,
}) {
  final widgets = <pw.Widget>[];

  // ================= TOTAL ACCUMULATORS =================

  double grandTotal = 0;
  final Map<String, double> allCountryKm = {};

  // ================= ROUNDS =================

  for (int i = 0; i < offer.rounds.length; i++) {
    final round = offer.rounds[i];
    final result = calc[i];

    if (round.entries.isEmpty || result == null) continue;

    // ➜ Summer total
    if (result.totalCost != null) {
      grandTotal += result.totalCost!;
    }

    // ➜ Summer km per land
    for (final entry in round.entries) {
      entry.countryKm.forEach((country, km) {
        if (km <= 0) return;

        allCountryKm[country] =
            (allCountryKm[country] ?? 0) + km;
      });
    }

    // ---------------- ROUND TITLE
    widgets.add(
      pw.Text(
  "${S.t('round', lang: offer.language)} ${roundNumberOverride ?? (i + 1)}",
  style: pw.TextStyle(font: bold, fontSize: 12),

      ),
    );

    widgets.add(pw.SizedBox(height: 8));

    // ---------------- HEADERS
    final headers = [
      S.t('date', lang: offer.language),
      S.t('location', lang: offer.language),
      S.t('km', lang: offer.language),
      S.t('pdfTime', lang: offer.language),
      S.t('extra', lang: offer.language),
    ];

    final rows = <List<String>>[];

    // ---------------- ROWS
    // Matches new_offer_page logic:
    //  - Travel/Off rows: always 0 km, no extra
    //  - First Travel in a consecutive block: show the merged km from prev city → next city
    //  - Subsequent Travel rows: 0 km
    //  - City after Travel: 0 km (already shown on first Travel row)

    // Pre-calculate: for each Travel row, is it the FIRST in a consecutive Travel block?
    final isFirstTravel = List<bool>.filled(round.entries.length, false);
    for (int r = 0; r < round.entries.length; r++) {
      final loc = round.entries[r].location.trim().toLowerCase();
      if (loc != 'travel') continue;
      // Check if previous entry is also Travel
      bool prevIsTravel = false;
      if (r > 0) {
        final prevLoc = round.entries[r - 1].location.trim().toLowerCase();
        prevIsTravel = prevLoc == 'travel';
      }
      isFirstTravel[r] = !prevIsTravel;
    }

for (int r = 0; r < round.entries.length; r++) {
  final e = round.entries[r];
  final loc = e.location.trim().toLowerCase();
  final isTravel = loc == 'travel';
  final isOff = loc == 'off';

  // Is this a city that comes after one or more Travel rows?
  bool isAfterTravel = false;
  if (!isTravel && !isOff) {
    for (int j = r - 1; j >= 0; j--) {
      final jLoc = round.entries[j].location.trim().toLowerCase();
      if (jLoc == 'travel') { isAfterTravel = true; break; }
      if (jLoc.isNotEmpty && jLoc != 'off') break;
    }
  }

  double displayKm = 0;
  String extraText = '';

  if (isOff || isAfterTravel) {
    // Off days and cities after Travel: always 0 km, no extra
    displayKm = 0;
  } else if (isTravel) {
    if (isFirstTravel[r]) {
      // First Travel in block: show merged km (prev real city → next real city)
      // Find next real city's km from calc result
      for (int j = r + 1; j < round.entries.length; j++) {
        final jLoc = round.entries[j].location.trim().toLowerCase();
        if (jLoc == 'travel' || jLoc == 'off' || jLoc.isEmpty) continue;
        // Found next real city — use its legKm
        if (j < result.legKm.length) {
          displayKm = result.legKm[j].toDouble();
        }
        // Get extra/DDrive from that city
        final jNoDDrive = j < result.noDDrivePerLeg.length
            ? result.noDDrivePerLeg[j] : false;
        final jHasDDrive = !jNoDDrive && displayKm > 600;
        final jExtra = j < result.extraPerLeg.length ? result.extraPerLeg[j] : '';
        extraText = _buildExtraText(hasDDrive: jHasDDrive, extraField: jExtra);
        break;
      }
      // Fallback: use own km if calc put it on the Travel row
      if (displayKm == 0 && r < result.legKm.length) {
        displayKm = result.legKm[r].toDouble();
        if (displayKm > 0) {
          final ownNoDDrive = r < result.noDDrivePerLeg.length
              ? result.noDDrivePerLeg[r] : false;
          final hasDDrive = !ownNoDDrive && displayKm > 600;
          final rawExtra = r < result.extraPerLeg.length ? result.extraPerLeg[r] : '';
          extraText = _buildExtraText(hasDDrive: hasDDrive, extraField: rawExtra);
        }
      }
    } else {
      // Subsequent Travel in block: 0 km
      displayKm = 0;
    }
  } else {
    // Normal city row (no Travel before it)
    if (r < result.legKm.length) displayKm = result.legKm[r].toDouble();
    final legIsNoDDrive = r < result.noDDrivePerLeg.length
        ? result.noDDrivePerLeg[r] : false;
    final hasDDrive = !legIsNoDDrive && displayKm > 600;
    final rawExtra = r < result.extraPerLeg.length ? result.extraPerLeg[r] : '';
    extraText = _buildExtraText(hasDDrive: hasDDrive, extraField: rawExtra);
  }

  // Show the date only on the first row of each day — blank it on consecutive
  // rows that share the same date.
  final prevDate = r > 0 ? round.entries[r - 1].date : null;
  final bool sameDateAsPrev = prevDate != null &&
      prevDate.year == e.date.year &&
      prevDate.month == e.date.month &&
      prevDate.day == e.date.day;

  rows.add([
    sameDateAsPrev ? "" : DateFormat("dd.MM.yyyy").format(e.date),
    e.location,
    displayKm > 0 ? "${displayKm.round()}" : "",
    displayKm > 0 ? _calcTimeText(km: displayKm, hasDDrive: false) : "",
    extraText,
  ]);
}

    // ---------------- TABLE
    widgets.add(
      pw.Table.fromTextArray(
        headers: headers,
        data: rows,

        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(1),
        },

        headerAlignment: pw.Alignment.centerLeft,

        cellAlignments: {
          for (int i = 0; i < headers.length; i++)
            i: pw.Alignment.centerLeft,
        },

        headerStyle: pw.TextStyle(font: bold, fontSize: 9),
        cellStyle: pw.TextStyle(font: regular, fontSize: 8),

        border: pw.TableBorder(
          horizontalInside:
              pw.BorderSide(color: PdfColors.grey400),
          verticalInside:
              pw.BorderSide(color: PdfColors.grey400),
          top: pw.BorderSide(color: PdfColors.grey600),
          bottom: pw.BorderSide(color: PdfColors.grey600),
        ),
      ),
    );

    // ---------------- SUBTOTAL (PER ROUND, override takes priority)
    final subtotal = subtotalOverride ?? result.totalCost;
    if (subtotal != null) {
      widgets.add(pw.SizedBox(height: 6));

      widgets.add(
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            "${S.t('pdfSubtotal', lang: offer.language)}: ${_formatNok(subtotal)}",
            style: pw.TextStyle(
              font: bold,
              fontSize: 9,
            ),
          ),
        ),
      );
    }

    widgets.add(pw.SizedBox(height: 25));
  }

  

  // ================= WRAPPER =================

  return widgets
    .map(
      (w) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 40),
        child: w,
      ),
    )
    .toList();
}


  // ============================================================
  // TERMS
  // ============================================================

  static pw.Widget _buildTerms(
    pw.Font regular,
    pw.Font bold, {
    CompanyBranding? branding,
    String language = 'no',
  }) {
    final resolved = branding?.termsFor(language);
    final terms = (resolved != null && resolved.trim().isNotEmpty)
        ? resolved
        : _termsText;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Paragraph(
        text: terms,
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

  static pw.Widget _buildSignature(
    pw.Font font,
    pw.Font bold,
    String customerCompany, {
    String? customerSignature,
    String? customerSignatureDate,
    String? companySignature,
    String? companySignatureDate,
    CompanyBranding? branding,
    String language = 'no',
  }) {
    final forLabel = S.t('pdfFor', lang: language);
    final customerFallback = S.t('pdfCustomer', lang: language);
    final dateLabel = S.t('date', lang: language);
    final nameTitleDate = S.t('pdfNameAndTitleDate', lang: language);

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Row(
        children: [
          // Company side (CSS)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  branding?.signatureName != null && branding!.signatureName!.isNotEmpty
                      ? branding.signatureName!
                      : 'For Coach Service Scandinavia',
                  style: pw.TextStyle(font: bold, fontSize: 10),
                ),
                pw.SizedBox(height: 6),
                if (companySignature != null) ...[
                  pw.Text(
                    companySignature,
                    style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.blue900),
                  ),
                  pw.SizedBox(height: 4),
                ] else
                  pw.SizedBox(height: 24),
                pw.Container(
                  height: 1,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  companySignature != null
                      ? '$companySignature  ·  $dateLabel: ${companySignatureDate ?? ''}'
                      : nameTitleDate,
                  style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 40),
          // Customer side
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '$forLabel ${customerCompany.isNotEmpty ? customerCompany : customerFallback}',
                  style: pw.TextStyle(font: bold, fontSize: 10),
                ),
                pw.SizedBox(height: 6),
                if (customerSignature != null) ...[
                  pw.Text(
                    customerSignature,
                    style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.blue900),
                  ),
                  pw.SizedBox(height: 4),
                ] else
                  pw.SizedBox(height: 24),
                pw.Container(
                  height: 1,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  customerSignature != null
                      ? '$customerSignature  ·  $dateLabel: ${customerSignatureDate ?? ''}'
                      : nameTitleDate,
                  style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
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
static String _todayDate() {
  return DateFormat("dd.MM.yyyy").format(DateTime.now());
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

    if (extraField.trim().isNotEmpty) {
      extras.add(extraField.trim());
    }

    return extras.join("/");
  }

  // ============================================================
// VAT ENGINE (PDF - SOURCE OF TRUTH)
// ============================================================

// VAT rates (same as NewOfferPage)
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

// --------------------------------------------
// Calculate foreign VAT
// --------------------------------------------
static Map<String, double> _calculateForeignVat({
  required double basePrice,
  required Map<String, double> countryKm,
  double? totalDrivenKm,
  double? totalExVat,
}) {
  // Moss Turbusser (truck): 25% Norwegian MVA on the full sum of the trips
  // (incl ferry/bridge/toll), not pro-rated by km share.
  if (activeCompanyNotifier.value?.name == 'Moss Turbusser') {
    final basis = totalExVat ?? basePrice;
    if (basis <= 0) return {};
    final hasForeignKm = countryKm.values.any((km) => km > 0);
    if (!hasForeignKm) return {};
    return {'NO': basis * 0.25};
  }

  if (basePrice <= 0 || countryKm.isEmpty) return {};

  final totalKm = totalDrivenKm ??
      countryKm.values.fold<double>(0, (a, b) => a + b);

  if (totalKm <= 0) return {};

  final Map<String, double> result = {};

  countryKm.forEach((country, km) {
    if (km <= 0) return;

    final rate = _vatRates[country] ?? 0;
    if (rate <= 0) return;

    final share = km / totalKm;
    // basePrice is excl VAT. VAT is added on top.
    final vat = basePrice * share * rate;

    if (vat > 0) {
      result[country] = vat;
    }
  });

  return result;
}
// --------------------------------------------
// VAT BOX (PDF - ultra tight layout)
// --------------------------------------------
static pw.Widget _buildVatBox(
  Map<String, double> vatMap,
  double excl,
  double incl,
  pw.Font regular,
  pw.Font bold, {
  String language = 'no',
}) {
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
      fontStyle:
          italic ? pw.FontStyle.italic : pw.FontStyle.normal,
    );

    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // LABEL (fast bredde)
        pw.SizedBox(
          width: labelWidth,
          child: pw.Text(
            label,
            style: style,
            textAlign: pw.TextAlign.right,
          ),
        ),

        pw.SizedBox(width: 6),

        // VALUE (fast bredde)
        pw.SizedBox(
          width: valueWidth,
          child: pw.Text(
            value,
            style: style,
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  final rows = <pw.Widget>[];

  // ---- EXCL
  rows.add(
    row(
      S.t('totalExclVat', lang: language),
      _formatNok(excl),
      boldText: true,
    ),
  );

  // ---- VAT
  final isMossTruck =
      activeCompanyNotifier.value?.name == 'Moss Turbusser';
  final vatLabel = S.t('vat', lang: language);
  vatMap.forEach((country, value) {
    final rate = isMossTruck
        ? 25
        : ((_vatRates[country] ?? 0) * 100).round();

    rows.add(
      row(
        "$vatLabel $country $rate%",
        _formatNok(value),
        italic: true,
      ),
    );
  });

  rows.add(pw.SizedBox(height: 4));

  // Divider
  rows.add(
    pw.Container(
      width: labelWidth + valueWidth + 6,
      height: 0.5,
      color: PdfColors.grey,
    ),
  );

  rows.add(pw.SizedBox(height: 4));

  // ---- INCL
  rows.add(
    row(
      S.t('totalInclVat', lang: language),
      _formatNok(incl),
      boldText: true,
    ),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: rows,
  );
}



  // ============================================================
  // RIGHT INFO
  // ============================================================

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
              style: pw.TextStyle(font: font, fontSize: 8),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: font, fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

} // 👈 DENNE MÅ MED