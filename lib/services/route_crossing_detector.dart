import 'dart:math';

import 'package:latlong2/latlong.dart';

enum _CrossingType { bridge, ferry }

class _KnownCrossing {
  final String name;
  final double lat;
  final double lon;
  final double radiusKm;
  final _CrossingType type;

  const _KnownCrossing(this.name, this.lat, this.lon, this.radiusKm, this.type);
}

/// Result of ferry/bridge auto-detection for a single route.
class CrossingDetectionResult {
  final bool hasFerry;
  final bool hasBridge;

  /// All crossing names in route order (bridges + ferries mixed).
  final List<String> crossingNames;

  CrossingDetectionResult({
    required this.hasFerry,
    required this.hasBridge,
    required this.crossingNames,
  });

  /// Combined display name in route order, joined by &
  /// Example: "Larvik - Hirtshals&Storebæltsbroen&Rødby - Puttgarden"
  String get combinedName => crossingNames.join('&');
}

class RouteCrossingDetector {
  static const List<_KnownCrossing> _allCrossings = [
    // Bridges
    _KnownCrossing('Öresundsbroen', 55.57, 12.85, 5, _CrossingType.bridge),
    _KnownCrossing('Storebæltsbroen', 55.34, 11.04, 5, _CrossingType.bridge),
    _KnownCrossing('Fehmarnsundbrücke', 54.40, 11.17, 3, _CrossingType.bridge),

    // Ferries
    _KnownCrossing('Rødby - Puttgarden', 54.575, 11.28, 10, _CrossingType.ferry),
    _KnownCrossing('Gedser - Rostock', 54.30, 12.10, 15, _CrossingType.ferry),
    _KnownCrossing('Helsingør - Helsingborg', 56.04, 12.62, 5, _CrossingType.ferry),
    _KnownCrossing('Larvik - Hirtshals', 58.32, 10.00, 30, _CrossingType.ferry),
  ];

  /// Detect all crossings in polyline order.
  static CrossingDetectionResult detect({
    required bool hasFerrySteps,
    required List<String> apiFerryNames,
    required List<LatLng> polylinePoints,
  }) {
    // Track first polyline index where each crossing is hit
    final Map<_KnownCrossing, int> hitIndex = {};

    for (final crossing in _allCrossings) {
      for (int i = 0; i < polylinePoints.length; i++) {
        final p = polylinePoints[i];
        final dist =
            _haversineKm(p.latitude, p.longitude, crossing.lat, crossing.lon);
        if (dist <= crossing.radiusKm) {
          hitIndex[crossing] = i;
          break;
        }
      }
    }

    // Sort by polyline order
    final sorted = hitIndex.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    bool hasBridge = false;
    bool hasFerry = hasFerrySteps;
    final names = <String>[];

    for (final entry in sorted) {
      names.add(entry.key.name);
      if (entry.key.type == _CrossingType.bridge) hasBridge = true;
      if (entry.key.type == _CrossingType.ferry) hasFerry = true;
    }

    return CrossingDetectionResult(
      hasFerry: hasFerry,
      hasBridge: hasBridge,
      crossingNames: names,
    );
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);
}
