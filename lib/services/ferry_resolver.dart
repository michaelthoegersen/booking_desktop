import '../models/ferry_definition.dart';

class FerryResolver {

  /// 🔧 Slå av/på debug her
  static const bool debug = true;

  static void _log(String msg) {
    if (debug) {
      // ignore: avoid_print
      print('[FERRY] $msg');
    }
  }

  // ---------------------------------------------------
  // Normaliser streng for trygg matching
  // ---------------------------------------------------
  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[æä]'), 'a')
        .replaceAll(RegExp(r'[øö]'), 'o')
        .replaceAll(RegExp(r'[å]'), 'a')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '')
        .replaceAll('–', '')
        .replaceAll('&', '')
        .replaceAll('/', '')
        .trim();
  }

  // ---------------------------------------------------
  // Splitter flere ferger i én tekst
  // ---------------------------------------------------
  static List<String> _split(String value) {
    return value
        .split(RegExp(r'[&,/]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // ===================================================
  // ✅ FERGE-RESOLVER – NAVN → PRIS
  // ===================================================
  ///
  /// - Bruker KUN ferryPerLeg (fra routes_all.ferry_name)
  /// - Matcher mot FerryDefinition.name
  /// - Støtter flere ferger per leg
  /// - Ingen legacy fallback
  ///
  static double resolveTotalFerryCost({
    required List<FerryDefinition> ferries,
    required bool trailer,
    required List<String?> ferryPerLeg,
  }) {
    double total = 0;

    _log('--- START FERRY RESOLVE ---');
    _log('Trailer: $trailer');
    _log('Ferries available: ${ferries.map((f) => f.name).join(', ')}');
    _log('Ferry per leg: $ferryPerLeg');

    for (int i = 0; i < ferryPerLeg.length; i++) {
      final raw = ferryPerLeg[i];

      if (raw == null || raw.trim().isEmpty) {
        _log('[$i] Skip – no ferry');
        continue;
      }

      final parts = _split(raw);
      final Set<String> counted = {};

      _log('[$i] Raw: "$raw" → parts: $parts');

      for (final part in parts) {
        final normalizedPart = _normalize(part);

        for (final ferry in ferries) {
          final normalizedFerry = _normalize(ferry.name);

          final bool matches =
              normalizedPart.contains(normalizedFerry) ||
              normalizedFerry.contains(normalizedPart);

          if (!matches) continue;

          if (counted.contains(ferry.name)) {
            _log('[$i] ⚠️ Already counted: ${ferry.name}');
            continue;
          }

          final price =
              trailer && ferry.trailerPrice != null
                  ? ferry.trailerPrice!
                  : ferry.price;

          total += price;
          counted.add(ferry.name);

          _log('[$i] ✅ MATCH: ${ferry.name}');
          _log('[$i]    Price added: $price');
        }
      }
    }

    _log('TOTAL FERRY COST: $total');
    _log('--- END FERRY RESOLVE ---');

    return total;
  }
}