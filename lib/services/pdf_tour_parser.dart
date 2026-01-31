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

  ParsedRound({
    required this.startLocation,
    required this.entries,
  });
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
  // PARSER
  // ======================================================

  static List<ParsedRound> parse(String rawText) {

    print("===== PARSER START =====");

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
  // ROUTE PARSER
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
  // META FILTER
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