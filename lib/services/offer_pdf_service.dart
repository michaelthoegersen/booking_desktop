// lib/services/offer_pdf_service.dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/offer_draft.dart';
import '../models/app_settings.dart';
import '../services/trip_calculator.dart';

class OfferPdfService {
  static Future<Uint8List> buildPdf({
    required OfferDraft offer,
    required AppSettings settings,
    required Map<int, RoundCalcResult> roundCalcByIndex,
  }) async {
    // ✅ Background template ONLY
    final template = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/template_page0.png')).buffer.asUint8List(),
    );

    final doc = pw.Document();

    // Used rounds (only those that contain entries or start location)
    final usedRounds = <int>[];
    for (int i = 0; i < offer.rounds.length; i++) {
      final r = offer.rounds[i];
      if (r.entries.isNotEmpty || r.startLocation.trim().isNotEmpty) {
        usedRounds.add(i);
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          return pw.Stack(
            children: [
              // ✅ template full page
              pw.Positioned.fill(
                child: pw.Image(template, fit: pw.BoxFit.cover),
              ),

              // ✅ Fill-in LEFT INFO (Company/Contact/Production)
              _posText(
                left: 170,
                top: 186,
                width: 250,
                text: offer.company,
                fontSize: 13,
                bold: true,
              ),
              _posText(
                left: 170,
                top: 214,
                width: 250,
                text: offer.contact,
                fontSize: 13,
                bold: true,
              ),
              _posText(
                left: 170,
                top: 242,
                width: 250,
                text: offer.production,
                fontSize: 13,
                bold: true,
              ),

              // ✅ Fill-in RIGHT INFO block (same values, but aligned to that panel)
              _posText(left: 595, top: 206, width: 180, text: offer.company, fontSize: 9),
              _posText(left: 595, top: 248, width: 180, text: offer.production, fontSize: 9),
              _posText(left: 595, top: 270, width: 180, text: "${offer.busCount} x ${offer.busType.label}", fontSize: 9),
              _posText(
                left: 595,
                top: 292,
                width: 180,
                text: _offerDateSpan(offer),
                fontSize: 9,
              ),
              _posText(
                left: 595,
                top: 314,
                width: 180,
                text: _validUntil(),
                fontSize: 9,
              ),

              // ✅ ROUNDS
              ..._buildRounds(
                offer: offer,
                usedRounds: usedRounds,
                roundCalcByIndex: roundCalcByIndex,
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ============================================================
  // ROUNDS SECTION (Dynamic)
  // ============================================================

  static List<pw.Widget> _buildRounds({
    required OfferDraft offer,
    required List<int> usedRounds,
    required Map<int, RoundCalcResult> roundCalcByIndex,
  }) {
    if (usedRounds.isEmpty) return [];

    // ----- Coordinates for the “Round 1 block” in your template -----
    // 👇 these are the ONLY numbers you will tweak later
    const double blockLeft = 90;
    const double blockTop = 470; // start of first round
    const double blockWidth = 710;

    // Each round block height (roughly the same as template)
    // We do dynamic Y spacing based on actual number of rounds.
    const double blockHeight = 250;

    final widgets = <pw.Widget>[];

    double y = blockTop;

    for (final ri in usedRounds) {
      final round = offer.rounds[ri];
      final calc = roundCalcByIndex[ri];

      // sorted entries
      final entries = List<RoundEntry>.from(round.entries);
      entries.sort((a, b) => a.date.compareTo(b.date));

      // block header: "Round X" and "Start: ..."
      widgets.add(
        _posText(
          left: blockLeft,
          top: y,
          width: 140,
          text: "Round ${ri + 1}",
          fontSize: 14,
          bold: true,
        ),
      );

      widgets.add(
        _posText(
          left: blockLeft + 110,
          top: y + 1,
          width: 220,
          text: "Start: ${round.startLocation}",
          fontSize: 10,
          bold: false,
        ),
      );

      // trailer flag
      if (round.trailer) {
        widgets.add(
          _posText(
            left: blockLeft + blockWidth - 80,
            top: y,
            width: 80,
            text: "Trailer",
            fontSize: 10,
            bold: true,
            alignRight: true,
          ),
        );
      }

      // Table rows positions
      final rowStartY = y + 60; // first table row
      const rowHeight = 22;

      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];

        final from = (i == 0) ? round.startLocation : entries[i - 1].location;
        final to = e.location;

        // KM: we do not depend on calc.legKm (because your model doesn't have it)
        // We can’t compute leg km here unless you pass it in.
        // So we display "-" if missing.
        // (You can later pass legKmByRound if needed)
        final kmText = "-";

        // Time calc based on km if possible
        final timeText = "--";

        // Extra logic: D.Drive + Ferry/Bridge
        final extraText = _buildExtraText(
          hasDDrive: (calc?.dDriveDays ?? 0) > 0,
          extraField: (e.extra ?? ''),
        );

        widgets.add(
          _roundRow(
            left: blockLeft,
            top: rowStartY + (i * rowHeight),
            date: DateFormat("dd.MM.yyyy").format(e.date),
            route: "$from → $to",
            km: kmText,
            time: timeText,
            extra: extraText,
          ),
        );

        // stop if too many rows (avoid going outside the template round box)
        if (i >= 5) break;
      }

      // Totals box (bottom of round)
      final totalsTop = y + blockHeight - 55;

      widgets.add(
        _roundTotalsLine(
          left: blockLeft + 20,
          top: totalsTop,
          calc: calc,
        ),
      );

      y += blockHeight;
    }

    return widgets;
  }

  static pw.Widget _roundRow({
    required double left,
    required double top,
    required String date,
    required String route,
    required String km,
    required String time,
    required String extra,
  }) {
    // Column widths based on template
    const dateW = 95.0;
    const routeW = 360.0;
    const kmW = 60.0;
    const timeW = 90.0;
    const extraW = 110.0;

    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Row(
        children: [
          _cell(date, dateW, bold: true),
          _cell(route, routeW, bold: true),
          _cell(km, kmW, right: true),
          _cell(time, timeW, right: true),
          _cell(extra, extraW),
        ],
      ),
    );
  }

  static pw.Widget _roundTotalsLine({
    required double left,
    required double top,
    required RoundCalcResult? calc,
  }) {
    String nok(num v) => "${v.toStringAsFixed(0)},-";

    final day = nok(calc?.dayCost ?? 0);
    final extraKm = nok(calc?.extraKmCost ?? 0);
    final trailer = nok((calc?.trailerDayCost ?? 0) + (calc?.trailerKmCost ?? 0));
    final toll = nok(calc?.tollCost ?? 0);
    final total = nok(calc?.totalCost ?? 0);

    final trailerText =
        ((calc?.trailerDayCost ?? 0) + (calc?.trailerKmCost ?? 0)) > 0 ? "Trailer: $trailer," : "";

    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Row(
        children: [
          _mini("Days: $day,"),
          pw.SizedBox(width: 18),
          _mini("Extra km: $extraKm,"),
          pw.SizedBox(width: 18),
          if (trailerText.isNotEmpty) _mini(trailerText),
          if (trailerText.isNotEmpty) pw.SizedBox(width: 18),
          _mini("Toll: $toll,"),
          pw.SizedBox(width: 140),
          pw.Text(
            "TOTAL: $total",
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static pw.Widget _posText({
    required double left,
    required double top,
    required double width,
    required String text,
    required double fontSize,
    bool bold = false,
    bool alignRight = false,
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
          textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static pw.Widget _cell(String text, double width, {bool bold = false, bool right = false}) {
    return pw.SizedBox(
      width: width,
      child: pw.Text(
        text,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _mini(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    );
  }

  static String _validUntil() {
    // Example: 14 days validity
    final d = DateTime.now().add(const Duration(days: 14));
    return DateFormat("dd.MM.yyyy").format(d);
  }

  static String _offerDateSpan(OfferDraft offer) {
    DateTime? earliest;
    DateTime? latest;

    for (final r in offer.rounds) {
      for (final e in r.entries) {
        earliest = (earliest == null || e.date.isBefore(earliest)) ? e.date : earliest;
        latest = (latest == null || e.date.isAfter(latest)) ? e.date : latest;
      }
    }

    if (earliest == null) return "-";
    if (latest == null) return DateFormat("dd.MM.yyyy").format(earliest);

    return "${DateFormat("dd.MM.yyyy").format(earliest)} - ${DateFormat("dd.MM.yyyy").format(latest)}";
  }

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
          .where((s) => s.isNotEmpty)
          .toList();

      for (final p in parts) {
        final low = p.toLowerCase();
        if (low.contains("ferry")) {
          if (!extras.contains("Ferry")) extras.add("Ferry");
        } else if (low.contains("bridge")) {
          if (!extras.contains("Bridge")) extras.add("Bridge");
        }
      }
    }

    if (extras.isEmpty) return "-";
    return extras.join("/");
  }
}