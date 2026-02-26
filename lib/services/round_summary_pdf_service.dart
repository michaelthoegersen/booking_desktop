import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class RoundSummaryPdfService {
  static final _dateFmt = DateFormat('dd.MM.yyyy');

  // ============================================================
  // GOOGLE MAPS → ADDRESS
  // ============================================================

  static final _mapsUrlRe = RegExp(
    r'https?://(?:maps\.app\.goo\.gl|goo\.gl|(?:www\.)?google\.\w+/maps|maps\.google\.\w+)\S*',
  );

  /// Extract the actual place coordinates from a Google Maps URL.
  /// Prefers !3d...!4d... (place marker) over @lat,lng (map view center).
  static List<double>? _extractCoords(String url) {
    // !3d=lat !4d=lng — the actual place pin
    final pin = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(url);
    if (pin != null) {
      final lat = double.tryParse(pin.group(1)!);
      final lng = double.tryParse(pin.group(2)!);
      if (lat != null && lng != null) return [lat, lng];
    }

    // Fallback: @lat,lng
    final at = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
    if (at != null) {
      final lat = double.tryParse(at.group(1)!);
      final lng = double.tryParse(at.group(2)!);
      if (lat != null && lng != null) return [lat, lng];
    }

    return null;
  }

  /// Reverse-geocode coordinates via OpenStreetMap Nominatim → street address.
  static Future<String?> _reverseGeocode(double lat, double lng) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=$lat&lon=$lng&format=json&addressdetails=1',
    );
    final res = await http.get(url, headers: {
      'User-Agent': 'TourFlow/1.0',
    });
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = data['address'] as Map<String, dynamic>?;
    if (addr == null) return data['display_name'] as String?;

    final parts = <String>[];
    final road = addr['road'] ?? addr['pedestrian'] ?? addr['street'] ?? '';
    final houseNr = addr['house_number'] ?? '';
    if (road.toString().isNotEmpty) {
      parts.add(houseNr.toString().isNotEmpty
          ? '$road $houseNr'
          : road.toString());
    }
    final postcode = addr['postcode'] ?? '';
    final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
    if (city.toString().isNotEmpty) {
      parts.add(postcode.toString().isNotEmpty
          ? '$postcode $city'
          : city.toString());
    }

    return parts.isNotEmpty ? parts.join(', ') : data['display_name'] as String?;
  }

  /// Follow redirects on a URL (for short links like goo.gl).
  static Future<String> _followRedirects(String url) async {
    final client = http.Client();
    try {
      var current = url;
      for (var i = 0; i < 5; i++) {
        final request = http.Request('GET', Uri.parse(current))
          ..followRedirects = false;
        final response = await client.send(request);
        final location = response.headers['location'];
        if (!response.isRedirect || location == null) break;
        current = location.startsWith('http')
            ? location
            : Uri.parse(current).resolve(location).toString();
      }
      return current;
    } finally {
      client.close();
    }
  }

  /// Resolve a single Google Maps URL → street address.
  static Future<String> _resolveOneUrl(String url) async {
    try {
      var resolved = url;

      // Short links need redirect following
      if (url.contains('goo.gl')) {
        resolved = await _followRedirects(url);
      }

      // Extract coordinates and reverse-geocode
      final coords = _extractCoords(resolved);
      if (coords != null) {
        final address = await _reverseGeocode(coords[0], coords[1]);
        if (address != null && address.isNotEmpty) return address;
      }

      // Fallback: place name from URL path
      final placeMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(resolved);
      if (placeMatch != null) {
        return Uri.decodeComponent(
          placeMatch.group(1)!.replaceAll('+', ' '),
        );
      }
    } catch (_) {}

    return url;
  }

  /// Process a field that may contain text mixed with Google Maps URLs.
  /// Each URL is resolved to a street address.
  /// Multiple entries are placed on separate lines.
  static Future<String> _cleanField(String raw) async {
    if (raw.trim().isEmpty) return raw;
    if (!_mapsUrlRe.hasMatch(raw)) return raw;

    final lines = <String>[];
    var remaining = raw;

    while (_mapsUrlRe.hasMatch(remaining)) {
      final m = _mapsUrlRe.firstMatch(remaining)!;

      // Text before the URL (e.g. "Slependen: ")
      final prefix = remaining.substring(0, m.start).trim();

      // Resolve the URL
      final url = m.group(0)!;
      final address = await _resolveOneUrl(url);

      // Combine prefix + resolved address
      if (prefix.isNotEmpty) {
        var cleanPrefix = prefix.endsWith(':')
            ? prefix.substring(0, prefix.length - 1).trim()
            : prefix;
        // Remove quotation marks
        cleanPrefix = cleanPrefix.replaceAll('"', '').trim();
        lines.add('$cleanPrefix: $address');
      } else {
        lines.add(address);
      }

      remaining = remaining.substring(m.end).trim();
    }

    // Any leftover text without URLs
    if (remaining.isNotEmpty) {
      lines.add(remaining);
    }

    return lines.join('\n').replaceAll('"', '');
  }

  // ============================================================
  // GENERATE
  // ============================================================

  static Future<Uint8List> generate({
    required String production,
    required String bus,
    required String driver,
    required String status,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required List<Map<String, dynamic>> days,
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

    // Resolve Google Maps URLs → readable street addresses
    for (final day in days) {
      day['venue'] = await _cleanField((day['venue'] as String?) ?? '');
      day['adresse'] = await _cleanField((day['adresse'] as String?) ?? '');
      day['getin'] = await _cleanField((day['getin'] as String?) ?? '');
      day['kommentarer'] = await _cleanField((day['kommentarer'] as String?) ?? '');
    }

    // Date range
    final sortedDays = [...days]
      ..sort((a, b) => (a['dato'] as String).compareTo(b['dato'] as String));

    final fromDate = sortedDays.isNotEmpty
        ? _dateFmt.format(DateTime.parse(sortedDays.first['dato']))
        : '';
    final toDate = sortedDays.isNotEmpty
        ? _dateFmt.format(DateTime.parse(sortedDays.last['dato']))
        : '';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 40),
        build: (context) => [
          _buildTopBar(appLogo, regular),
          pw.SizedBox(height: 24),
          _buildTitle(production, bus, fromDate, toDate, regular, bold),
          pw.SizedBox(height: 16),
          _buildInfoBox(
            driver: driver,
            status: status,
            bus: bus,
            contactName: contactName,
            contactEmail: contactEmail,
            contactPhone: contactPhone,
            regular: regular,
            bold: bold,
          ),
          pw.SizedBox(height: 20),
          ...sortedDays.map(
            (day) => _buildDayCard(day, regular, bold),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ============================================================
  // BLACK BAR
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
            child: pw.Image(
              logo,
              height: 180,
              fit: pw.BoxFit.contain,
            ),
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
  // TITLE
  // ============================================================

  static pw.Widget _buildTitle(
    String production,
    String bus,
    String fromDate,
    String toDate,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TOUR SCHEDULE',
            style: pw.TextStyle(font: bold, fontSize: 20),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '$production  —  ${bus.replaceAll("_", " ")}',
            style: pw.TextStyle(font: regular, fontSize: 13),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '$fromDate – $toDate',
            style: pw.TextStyle(
              font: regular,
              fontSize: 11,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO BOX
  // ============================================================

  static pw.Widget _buildInfoBox({
    required String driver,
    required String status,
    required String bus,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _infoRow('Driver', driver, regular, bold),
                  _infoRow('Status', status, regular, bold),
                  _infoRow('Bus', bus.replaceAll("_", " "), regular, bold),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _infoRow('Contact', contactName, regular, bold),
                  if (contactEmail.isNotEmpty)
                    _infoRow('Email', contactEmail, regular, bold),
                  if (contactPhone.isNotEmpty)
                    _infoRow('Phone', contactPhone, regular, bold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _infoRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 55,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(font: bold, fontSize: 9),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DAY CARD
  // ============================================================

  static pw.Widget _buildDayCard(
    Map<String, dynamic> day,
    pw.Font regular,
    pw.Font bold,
  ) {
    final dato = _dateFmt.format(DateTime.parse(day['dato'] as String));
    final sted = (day['sted'] as String?) ?? '';
    final venue = (day['venue'] as String?) ?? '';
    final adresse = (day['adresse'] as String?) ?? '';
    final itinerary = (day['getin'] as String?) ?? '';
    final tid = (day['tid'] as String?) ?? '';
    final dDrive = (day['d_drive'] as String?) ?? '';
    final kommentar = (day['kommentarer'] as String?) ?? '';

    // Parse D.Drive km to check threshold
    final kmValue = double.tryParse(
      dDrive.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    final showDDrive = dDrive.trim().isNotEmpty && (kmValue == null || kmValue >= 600);

    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 40, right: 40, bottom: 12),
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Date + city header
            pw.Row(
              children: [
                pw.Text(dato, style: pw.TextStyle(font: bold, fontSize: 11)),
                if (sted.isNotEmpty) ...[
                  pw.SizedBox(width: 12),
                  pw.Text(
                    sted,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 11,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 6),

            // Fields
            if (venue.isNotEmpty) _cardRow('Venue', venue, regular, bold),
            if (adresse.isNotEmpty) _cardRow('Address', adresse, regular, bold),
            if (tid.isNotEmpty) _cardRow('Time', tid, regular, bold),
            if (itinerary.isNotEmpty)
              _cardRow('Itinerary', itinerary, regular, bold),
            if (showDDrive) _cardRow('D.Drive', dDrive, regular, bold),
            if (kommentar.isNotEmpty)
              _cardRow('Comments', kommentar, regular, bold),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cardRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(font: bold, fontSize: 9),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
