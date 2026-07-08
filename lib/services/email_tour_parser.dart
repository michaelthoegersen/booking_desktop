/// Parses tour routing from pasted email text.
///
/// Handles formats like:
///   07.08 Kortrijk, Belgium – Alcatraz Festival
///   01 okt Pickup Brussel airport - til Het Depot Leuven
///   04 okt kjøredag til Køln
///   07 okt Berlin - Day off
///   16 okt Drop of Århus
///   10.08 Travel day
class EmailTourParser {
  static List<ParsedTourStop> parse(String text, {int? defaultYear}) {
    final lines = text.split(RegExp(r'\r?\n'));
    final stops = <ParsedTourStop>[];
    String lastCity = '';

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final parsed = _parseDateFromLine(line, defaultYear: defaultYear);
      if (parsed == null) continue;

      final date = parsed.date;
      // Strip leading dashes/em-dashes (e.g. "— Copenhagen" → "Copenhagen")
      final rest = parsed.rest.replaceFirst(RegExp(r'^[-–—]+\s*'), '');
      final restLower = rest.toLowerCase();

      // --- Day off (can appear after city: "Berlin - Day off") ---
      if (_isDayOff(restLower)) {
        stops.add(ParsedTourStop(date: date, city: 'Off'));
        continue;
      }

      // --- Check if "day off" appears after a dash: "Berlin - Day off" ---
      final dayOffAfterCity = RegExp(r'^(.+?)\s*[-–—]\s*day\s*off', caseSensitive: false).firstMatch(rest);
      if (dayOffAfterCity != null) {
        stops.add(ParsedTourStop(date: date, city: 'Off'));
        continue;
      }

      // --- Travel / kjøredag ---
      if (_isTravel(restLower)) {
        stops.add(ParsedTourStop(date: date, city: 'Travel'));
        continue;
      }

      // --- Kjøredag with destination: "kjøredag til Køln" / "kjøredag Esbjerg" ---
      final kjoreMatch = RegExp(r'^kjøredag\s+(?:til\s+)?(.+)', caseSensitive: false).firstMatch(rest);
      if (kjoreMatch != null) {
        // It's a travel day — the destination is the next city but the day is Travel
        stops.add(ParsedTourStop(date: date, city: 'Travel'));
        continue;
      }

      // --- Pickup: "Pickup Brussel airport - til Het Depot Leuven" ---
      final pickupMatch = RegExp(r'^pickup\s+(.+)', caseSensitive: false).firstMatch(rest);
      if (pickupMatch != null) {
        final pickupRest = pickupMatch.group(1)!;
        // Extract first city (before dash or "til")
        final city = _extractFirstCity(pickupRest);
        if (city.isNotEmpty) lastCity = city;
        stops.add(ParsedTourStop(date: date, city: city.isNotEmpty ? city : lastCity));
        continue;
      }

      // --- Dropoff: "Drop of Århus" / "Dropoff Oslo S" ---
      final dropMatch = RegExp(r'^drop\s*-?\s*(?:of+|off)\s+(.+)', caseSensitive: false).firstMatch(rest);
      if (dropMatch != null) {
        final city = dropMatch.group(1)!.trim();
        if (city.isNotEmpty) lastCity = city;
        stops.add(ParsedTourStop(date: date, city: city));
        continue;
      }

      // --- Normal city line ---
      final city = _extractCity(rest);
      if (city.isNotEmpty) lastCity = city;

      stops.add(ParsedTourStop(
        date: date,
        city: city.isNotEmpty ? city : lastCity,
      ));
    }

    return stops;
  }

  // ============================================================
  // DATE PARSING — supports "07.08", "01 okt", "07.08.2026"
  // ============================================================

  static const _monthNames = {
    'jan': 1, 'january': 1, 'januar': 1,
    'feb': 2, 'february': 2, 'februar': 2,
    'mar': 3, 'march': 3, 'mars': 3, 'mär': 3,
    'apr': 4, 'april': 4,
    'mai': 5, 'may': 5, 'maj': 5,
    'jun': 6, 'june': 6, 'juni': 6,
    'jul': 7, 'july': 7, 'juli': 7,
    'aug': 8, 'august': 8, 'augusti': 8,
    'sep': 9, 'sept': 9, 'september': 9,
    'okt': 10, 'oct': 10, 'october': 10, 'oktober': 10,
    'nov': 11, 'november': 11,
    'des': 12, 'dec': 12, 'december': 12, 'desember': 12, 'dez': 12, 'dezember': 12,
  };

  static _DateParsed? _parseDateFromLine(String line, {int? defaultYear}) {
    // Format 1: dd.MM or dd.MM.yyyy or dd/MM
    final numMatch = RegExp(
      r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?\s+(.*)',
    ).firstMatch(line);

    if (numMatch != null) {
      final day = int.parse(numMatch.group(1)!);
      final month = int.parse(numMatch.group(2)!);
      final yearStr = numMatch.group(3);
      int year;
      if (yearStr != null) {
        year = int.parse(yearStr);
        if (year < 100) year += 2000;
      } else {
        year = defaultYear ?? DateTime.now().year;
      }
      return _DateParsed(DateTime(year, month, day), numMatch.group(4)!.trim());
    }

    // Format 2: dd monthname ... (e.g. "01 okt Pickup Brussel")
    // Also handles "01.okt" or "01 okt."
    final nameMatch = RegExp(
      r'^(\d{1,2})[.\s]+([a-zäöüæøå]+)\.?\s+(.*)',
      caseSensitive: false,
    ).firstMatch(line);

    if (nameMatch != null) {
      final day = int.parse(nameMatch.group(1)!);
      final monthStr = nameMatch.group(2)!.toLowerCase();
      final month = _monthNames[monthStr];
      if (month != null) {
        final year = defaultYear ?? DateTime.now().year;
        return _DateParsed(DateTime(year, month, day), nameMatch.group(3)!.trim());
      }
    }

    return null;
  }

  // ============================================================
  // TRAVEL / DAY OFF DETECTION
  // ============================================================

  static bool _isTravel(String s) {
    return s == 'travel' ||
        s == 'travel day' ||
        s.startsWith('travel day') ||
        s == 'kjøredag' ||
        s.startsWith('kjøredag');
  }

  static bool _isDayOff(String s) {
    return s == 'day off' ||
        s == 'off day' ||
        s == 'off' ||
        s == 'tbd' ||
        s.startsWith('day off') ||
        s.startsWith('off day');
  }

  // ============================================================
  // CITY EXTRACTION
  // ============================================================

  /// Extract city from "Pickup Brussel airport - til Het Depot Leuven"
  /// Returns first meaningful city before dash/til.
  static String _extractFirstCity(String rest) {
    // Remove "airport", "station", etc.
    var cleaned = rest.replaceAll(RegExp(r'\b(airport|station|gare|bahnhof|hbf)\b', caseSensitive: false), '');

    // Split on " - " or " til "
    final parts = cleaned.split(RegExp(r'\s*[-–—]\s*|\s+til\s+', caseSensitive: false));
    return parts.first.trim();
  }

  /// Extract city from a normal tour line.
  /// "Kortrijk, Belgium – Alcatraz Festival" → "Kortrijk"
  /// "Amsterdam - Melkweg Max" → "Amsterdam"
  /// "Berlin" → "Berlin"
  static String _extractCity(String rest) {
    // Split on dash/em-dash to separate city from venue
    final dashParts = rest.split(RegExp(r'\s*[–—-]\s*'));

    String cityPart;
    if (dashParts.length >= 2) {
      cityPart = dashParts[0].trim();
    } else {
      cityPart = rest;
    }

    // Remove parenthetical notes
    cityPart = cityPart.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

    // If there's a comma, take only the city (before comma = city, after = country)
    final commaParts = cityPart.split(',');
    if (commaParts.length >= 2) {
      return commaParts[0].trim();
    }

    return cityPart.trim();
  }

  // ============================================================
  // TOUR BLOCK SPLITTING
  // ============================================================

  static int? detectYear(String text) {
    final match = RegExp(r'20\d{2}').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  static List<String> splitTourBlocks(String text) {
    // Split on "Pause", blank line gaps (3+), or routing headers
    final pausePattern = RegExp(
      r'(?:^|\n)\s*(?:pause|---+)\s*(?:\n|$)',
      caseSensitive: false,
    );

    final headerPattern = RegExp(
      r'(?:^|\n)(\w+\s+\d{4}\s+routing[^\n]*)',
      caseSensitive: false,
    );

    // Try pause-based split first
    final pauseMatches = pausePattern.allMatches(text).toList();
    if (pauseMatches.isNotEmpty) {
      final blocks = <String>[];
      int start = 0;
      for (final m in pauseMatches) {
        final block = text.substring(start, m.start).trim();
        if (block.isNotEmpty) blocks.add(block);
        start = m.end;
      }
      final last = text.substring(start).trim();
      if (last.isNotEmpty) blocks.add(last);
      if (blocks.length > 1) return blocks;
    }

    // Try header-based split
    final matches = headerPattern.allMatches(text).toList();
    if (matches.length <= 1) return [text];

    final blocks = <String>[];
    for (int i = 0; i < matches.length; i++) {
      final s = matches[i].start;
      final e = i + 1 < matches.length ? matches[i + 1].start : text.length;
      blocks.add(text.substring(s, e).trim());
    }
    return blocks;
  }
}

class _DateParsed {
  final DateTime date;
  final String rest;
  _DateParsed(this.date, this.rest);
}

class ParsedTourStop {
  final DateTime date;
  final String city;

  ParsedTourStop({
    required this.date,
    required this.city,
  });

  @override
  String toString() => '${date.day}.${date.month} $city';
}
