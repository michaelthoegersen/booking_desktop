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

  // ---------------------------------------------------
  // Bridge detection by name
  // ---------------------------------------------------
  static bool _isBridge(String name) {
    final lower = name.toLowerCase();
    return lower.contains('bro') || lower.contains('bridge');
  }

  // ===================================================
  // ✅ FERGE-RESOLVER – NAVN → PRIS (legacy — returns combined)
  // ===================================================
  static double resolveTotalFerryCost({
    required List<FerryDefinition> ferries,
    required bool trailer,
    required List<String?> ferryPerLeg,
  }) {
    final r = resolveFerriesAndBridges(
      ferries: ferries,
      trailer: trailer,
      ferryPerLeg: ferryPerLeg,
    );
    return r.ferryCost + r.bridgeCost;
  }

  // ===================================================
  // ✅ FERGE+BRO RESOLVER – returnerer separate kostnader
  // ===================================================
  ///
  /// - Bruker KUN ferryPerLeg (fra routes_all.ferry_name)
  /// - Matcher mot FerryDefinition.name
  /// - Skiller ferry fra bridge basert på navn (inneholder 'bro'/'bridge')
  ///
  static ({double ferryCost, double bridgeCost}) resolveFerriesAndBridges({
    required List<FerryDefinition> ferries,
    required bool trailer,
    required List<String?> ferryPerLeg,
    List<bool>? noBridgePerLeg,
  }) {
    double ferryTotal = 0;
    double bridgeTotal = 0;

    _log('--- START FERRY/BRIDGE RESOLVE ---');
    _log('Trailer: $trailer');
    _log('Ferries available: ${ferries.map((f) => f.name).join(', ')}');
    _log('Ferry per leg: $ferryPerLeg');

    for (int i = 0; i < ferryPerLeg.length; i++) {
      final raw = ferryPerLeg[i];

      if (raw == null || raw.trim().isEmpty) {
        _log('[$i] Skip – no ferry/bridge');
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

          if (_isBridge(ferry.name)) {
            if (noBridgePerLeg != null && i < noBridgePerLeg.length && noBridgePerLeg[i]) {
              _log('[$i] ⛔ BRIDGE SKIPPED (no_bridge): ${ferry.name}');
            } else {
              bridgeTotal += price;
              _log('[$i] ✅ BRIDGE MATCH: ${ferry.name}');
            }
          } else {
            ferryTotal += price;
            _log('[$i] ✅ FERRY MATCH: ${ferry.name}');
          }
          _log('[$i]    Price added: $price');
          counted.add(ferry.name);
        }
      }
    }

    _log('TOTAL FERRY COST: $ferryTotal');
    _log('TOTAL BRIDGE COST: $bridgeTotal');
    _log('--- END FERRY/BRIDGE RESOLVE ---');

    return (ferryCost: ferryTotal, bridgeCost: bridgeTotal);
  }
}