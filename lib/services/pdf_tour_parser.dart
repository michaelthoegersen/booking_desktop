// lib/services/pdf_tour_parser.dart

import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';


// ======================================================
// MODELS
// ======================================================

class ParsedTourEntry {
  final DateTime date;
  final String location;

  ParsedTourEntry({
    required this.date,
    required this.location,
  });
}

class ParsedRound {
  final String startLocation;
  final List<ParsedTourEntry> entries;
  /// Optional price per round (parsed from NTTAS-style PDFs)
  final double? price;

  ParsedRound({
    required this.startLocation,
    required this.entries,
    this.price,
  });
}

/// Metadata extracted from the PDF header (company, contact, etc.)
class ParsedOfferMeta {
  final String? company;
  final String? contact;
  final String? phone;
  final String? email;
  final String? production;
  final String? vehicleType;

  ParsedOfferMeta({
    this.company,
    this.contact,
    this.phone,
    this.email,
    this.production,
    this.vehicleType,
  });
}

/// Full parse result
class ParsedOffer {
  final ParsedOfferMeta meta;
  final List<ParsedRound> rounds;

  ParsedOffer({required this.meta, required this.rounds});
}


// ======================================================
// SERVICE
// ======================================================

class PdfTourParser {

  // ======================================================
  // PICK + EXTRACT
  // ======================================================

  static Future<String?> pickAndExtractText() async {

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result == null) return null;

    final file = result.files.single;

    Uint8List? bytes;

    if (file.bytes != null) {
      bytes = file.bytes;
    }
    else if (file.path != null) {
      final f = File(file.path!);
      bytes = await f.readAsBytes();
    }
    else if (file.readStream != null) {
      final chunks = <int>[];

      await for (final c in file.readStream!) {
        chunks.addAll(c);
      }

      bytes = Uint8List.fromList(chunks);
    }

    if (bytes == null || bytes.isEmpty) {
      throw Exception("Could not read PDF file");
    }

    return extractText(bytes);
  }


  // ======================================================
  // TEXT EXTRACT
  // ======================================================

  static Future<String> extractText(Uint8List bytes) async {

    final document = PdfDocument(inputBytes: bytes);

    final extractor = PdfTextExtractor(document);

    final text = extractor.extractText();

    document.dispose();

    return text;
  }


  // ======================================================
  // AUTO-DETECT FORMAT AND PARSE
  // ======================================================

  static List<ParsedRound> parse(String rawText) {
    final result = parseWithMeta(rawText);
    return result.rounds;
  }

  static ParsedOffer parseWithMeta(String rawText) {
    // Detect NTTAS/truck format: has "Runde" + "Dato" + "Sted" headers
    if (_isNttasFormat(rawText)) {
      print("Detected NTTAS/truck format");
      return _parseNttas(rawText);
    }
    // Original CSS/Starcoach format
    print("Using CSS/Starcoach format");
    return ParsedOffer(
      meta: ParsedOfferMeta(),
      rounds: _parseCss(rawText),
    );
  }

  static bool _isNttasFormat(String text) {
    final lower = text.toLowerCase();
    return (lower.contains('runde') && lower.contains('sted') && lower.contains('km')) ||
        lower.contains('tilbud lastebil') ||
        lower.contains('norsk turnétransport');
  }


  // ======================================================
  // NTTAS / TRUCK FORMAT PARSER
  // ======================================================

  static ParsedOffer _parseNttas(String rawText) {
    print("===== NTTAS PARSER START =====");

    final lines = rawText.split('\n').map((e) => e.trim()).toList();

    // ── Extract metadata ──
    String? firma, navn, telefon, epost, band, kjoretoy;
    for (final line in lines) {
      if (line.startsWith('Firma:')) firma = line.substring(6).trim();
      else if (line.startsWith('Navn:')) navn = line.substring(5).trim();
      else if (line.startsWith('Telefon:')) telefon = line.substring(8).trim();
      else if (line.startsWith('Epost:')) epost = line.substring(6).trim();
      else if (line.startsWith('Band:')) band = line.substring(5).trim();
      else if (line.startsWith('Kjøretøy:')) kjoretoy = line.substring(9).trim();
    }

    print("Meta: firma=$firma, band=$band, kjøretøy=$kjoretoy");

    final meta = ParsedOfferMeta(
      company: firma,
      contact: navn,
      phone: telefon,
      email: epost,
      production: band,
      vehicleType: kjoretoy,
    );

    // ── Find table start ──
    // Look for the header row with "Runde" "Dato" "Sted"
    int tableStart = -1;
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      if (l.contains('runde') && l.contains('dato') && l.contains('sted')) {
        tableStart = i + 1;
        break;
      }
    }

    if (tableStart == -1) {
      // Fallback: look for first round number
      for (int i = 0; i < lines.length; i++) {
        if (RegExp(r'^1\s').hasMatch(lines[i]) && i > 10) {
          tableStart = i;
          break;
        }
      }
    }

    if (tableStart == -1) {
      print("Could not find table start");
      return ParsedOffer(meta: meta, rounds: []);
    }

    print("Table starts at line $tableStart");

    // ── Parse rounds ──
    final rounds = <ParsedRound>[];
    final dateRegex = RegExp(r'(\d{2}\.\d{2}\.\d{4})');
    final roundNumRegex = RegExp(r'^\d{1,2}\s');
    final priceRegex = RegExp(r'(\d[\d\s]*[\d],\d{2})$');
    // Also match "kr 22 000,00" or just "22 000,00" at end of line
    final priceLine = RegExp(r'kr\s+([\d\s]+[\d],\d{2})');

    List<ParsedTourEntry> currentEntries = [];
    double? currentPrice;
    bool inRound = false;

    for (int i = tableStart; i < lines.length; i++) {
      final line = lines[i];

      // Stop at "Totalt eks MVA" or similar
      if (line.toLowerCase().startsWith('totalt') ||
          line.toLowerCase().startsWith('eventuelle ekstra') ||
          line.toLowerCase().startsWith('i tillegg')) {
        break;
      }

      // New round number at start of line
      if (roundNumRegex.hasMatch(line)) {
        // Save previous round
        if (currentEntries.isNotEmpty) {
          final startLoc = currentEntries.length > 1
              ? currentEntries.first.location
              : 'Moss';
          rounds.add(ParsedRound(
            startLocation: startLoc,
            entries: List.from(currentEntries),
            price: currentPrice,
          ));
        }
        currentEntries = [];
        currentPrice = null;
        inRound = true;
      }

      // Check for price line (e.g. "kr 22 000,00")
      final priceMatch = priceLine.firstMatch(line);
      if (priceMatch != null) {
        final priceStr = priceMatch.group(1)!.replaceAll(' ', '').replaceAll(',', '.');
        currentPrice = double.tryParse(priceStr);
      }

      // Skip summary lines like "2 dager", "350 km"
      if (RegExp(r'^\d+\s+dager?$').hasMatch(line) ||
          RegExp(r'^leie$', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^\d+\s+km$').hasMatch(line)) {
        continue;
      }

      // Parse date + location from the line
      final dateMatch = dateRegex.firstMatch(line);
      if (dateMatch != null && inRound) {
        final dateStr = dateMatch.group(1)!;
        final date = _parseDate(dateStr);
        if (date == null) continue;

        // Extract location: text after date, before km value
        // Line format: "26.05.2026 Oslo 100 km 1t 40m"
        // or just: "Lørenskog 20 km 0t 20m" (no date, continuation)
        String afterDate = line.substring(dateMatch.end).trim();
        // Remove round number prefix if present
        if (roundNumRegex.hasMatch(line)) {
          final withoutRound = line.replaceFirst(RegExp(r'^\d{1,2}\s+'), '');
          final dm = dateRegex.firstMatch(withoutRound);
          if (dm != null) {
            afterDate = withoutRound.substring(dm.end).trim();
          }
        }

        // Extract location (before km/time data)
        final locMatch = RegExp(r'^([A-Za-zÆØÅæøåÄÖäö\s\.\-]+?)(?:\s+\d)').firstMatch(afterDate);
        final location = locMatch != null
            ? locMatch.group(1)!.trim()
            : afterDate.replaceAll(RegExp(r'\d.*'), '').trim();

        if (location.isNotEmpty && location.toLowerCase() != 'off' && location.toLowerCase() != 'travel') {
          currentEntries.add(ParsedTourEntry(date: date, location: location));
          print("  Round ${rounds.length + 1}: ${date.toIso8601String()} → $location");
        }
      } else if (inRound && !line.contains('km') && !line.contains('dager')) {
        // Continuation line with just location (no date)
        // Try to parse as location with previous date
        // These are multi-stop lines like "Lørenskog 20 km 0t 20m"
        final locLine = line.replaceFirst(RegExp(r'^\d{1,2}\s+'), '');
        final locMatch = RegExp(r'^([A-Za-zÆØÅæøåÄÖäö\s\.\-]+?)(?:\s+\d)').firstMatch(locLine);
        if (locMatch != null && currentEntries.isNotEmpty) {
          final loc = locMatch.group(1)!.trim();
          if (loc.isNotEmpty && loc.toLowerCase() != 'off' && loc.toLowerCase() != 'travel') {
            currentEntries.add(ParsedTourEntry(
              date: currentEntries.last.date,
              location: loc,
            ));
            print("  Round ${rounds.length + 1}: (cont) → $loc");
          }
        }
      }
    }

    // Save last round
    if (currentEntries.isNotEmpty) {
      final startLoc = currentEntries.length > 1
          ? currentEntries.first.location
          : 'Moss';
      rounds.add(ParsedRound(
        startLocation: startLoc,
        entries: List.from(currentEntries),
        price: currentPrice,
      ));
    }

    print("NTTAS rounds found: ${rounds.length}");
    return ParsedOffer(meta: meta, rounds: rounds);
  }


  // ======================================================
  // CSS / STARCOACH FORMAT PARSER (original)
  // ======================================================

  static List<ParsedRound> _parseCss(String rawText) {

    print("===== CSS PARSER START =====");

    final rawLines = rawText
        .split('\n')
        .map((e) => e.trim())
        .toList();

    final List<String> lines = [];

    bool inTable = false;

    // ---------------- Find table ----------------
    for (final l in rawLines) {

      if (l.toLowerCase() == 'route') {
        inTable = true;
        continue;
      }

      if (!inTable) continue;
      if (_isMetaField(l)) continue;

      lines.add(l);
    }

    print("Table lines: ${lines.length}");

    final dateRegex = RegExp(
      r'^(\d{4}-\d{2}-\d{2}|\d{2}\.\d{2}\.\d{4})$',
    );

    final List<ParsedRound> rounds = [];

    ParsedRound? currentRound;
    DateTime? lastDate;

    bool lastWasDash = false;


    for (int i = 0; i < lines.length; i++) {

      final line = lines[i];

      // =====================================
      // DASH BREAK
      // =====================================
      if (line == '-') {

        if (lastWasDash) {
          print("=== DASH ROUND BREAK ===");
          currentRound = null;
          lastDate = null;
        }

        lastWasDash = true;
        continue;
      }

      lastWasDash = false;


      // =====================================
      // DATE
      // =====================================
      if (!dateRegex.hasMatch(line)) continue;

      final date = _parseDate(line);
      if (date == null) continue;


      // =====================================
      // DATE GAP BREAK
      // =====================================
      if (lastDate != null) {

        final diff = date.difference(lastDate!).inDays;

        if (diff >= 3) {
          print("=== DATE GAP BREAK ($diff days) ===");
          currentRound = null;
        }
      }

      lastDate = date;


      if (i + 1 >= lines.length) continue;

      final routeLine = lines[i + 1];
      if (routeLine.isEmpty) continue;


      final lower = routeLine.toLowerCase();
      final isFram = lower.startsWith('framkörd');

      final rawParts = _splitRawRoute(routeLine);
      final cities = _parseRoute(routeLine);

      if (cities.isEmpty) continue;


      // =====================================
      // NEW ROUND
      // =====================================
      if (currentRound == null) {

        String start;
        List<String> firstEntries = [];

        // ---------- FIRST ROUND ----------
        if (rounds.isEmpty) {
          start = 'Linköping';
          firstEntries = cities;
        }

        // ---------- NEXT ROUNDS ----------
        else {

          if (isFram) {
            start = cities.first;
            firstEntries = cities;
          }

          else if (rawParts.length >= 2) {
            start = rawParts.first;
            firstEntries = [rawParts[1]];
          }

          else {
            start = cities.first;
            firstEntries = cities;
          }
        }

        currentRound = ParsedRound(
          startLocation: start,
          entries: [],
        );

        rounds.add(currentRound);

        print("New round, start=$start");

        // Første entries
        for (final city in firstEntries) {

          currentRound.entries.add(
            ParsedTourEntry(
              date: date,
              location: city,
            ),
          );

          print("  + ${date.toIso8601String()} → $city");
        }

        continue;
      }


      // =====================================
      // NORMAL ADD
      // =====================================
      for (final city in cities) {

        currentRound.entries.add(
          ParsedTourEntry(
            date: date,
            location: city,
          ),
        );

        print("  + ${date.toIso8601String()} → $city");
      }
    }

    print("Rounds found: ${rounds.length}");

    return rounds;
  }


  // ======================================================
  // HELPERS
  // ======================================================

  static DateTime? _parseDate(String s) {
    try {

      DateTime d;

      if (s.contains('-')) {
        d = DateTime.parse(s);
      }

      else if (s.contains('.')) {
        final p = s.split('.');
        d = DateTime(
          int.parse(p[2]),
          int.parse(p[1]),
          int.parse(p[0]),
        );
      }

      else {
        return null;
      }

      return DateTime(d.year, d.month, d.day);

    } catch (_) {
      return null;
    }
  }


  // ======================================================
  // ROUTE PARSER (CSS format)
  // ======================================================

  static List<String> _parseRoute(String s) {

    var t = s.trim();
    final lower = t.toLowerCase();

    final isFram = lower.startsWith('framkörd');

    // ---------------- FRAMKÖRD ----------------
    if (isFram) {

      t = t.substring(8).trim();

      final parts = _splitRawRoute(t);

      print("FRAM: $parts");

      return parts;
    }

    // ---------------- NORMAL ----------------

    final parts = _splitRawRoute(t);

    if (parts.isEmpty) return [];

    final dest = parts.last;

    print("NORMAL: $parts → $dest");

    return [dest];
  }


  static List<String> _splitRawRoute(String s) {

    return s
        .split(RegExp(r'[-–]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }


  // ======================================================
  // META FILTER (CSS format)
  // ======================================================

  static bool _isMetaField(String s) {

    final t = s.toLowerCase();

    return t.contains('client') ||
        t.contains('period') ||
        t.contains('address') ||
        t.contains('zip') ||
        t.contains('bus') ||
        t.contains('contact') ||
        t.contains('phone') ||
        t.contains('email') ||
        t.contains('inkluderat') ||
        t.contains('extra') ||
        t.contains('starcoach') ||
        t.contains('vat') ||
        t.contains('price') ||
        t.contains('offert') ||
        t.contains('page');
  }
}
