import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A single toll station with coordinates and prices.
class TollStation {
  final int id;
  final String name;
  final double lat;
  final double lon;
  final double priceCar;
  final double priceCarRush;

  const TollStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.priceCar,
    required this.priceCarRush,
  });
}

/// Result of toll calculation for a route.
class TollResult {
  final double totalCost;
  final List<TollStation> passedStations;

  const TollResult({required this.totalCost, required this.passedStations});
}

/// Service that loads Norwegian toll stations from NVDB and matches them
/// against a route polyline to calculate toll costs.
class TollService {
  static const _base = 'https://nvdbapiles.atlas.vegvesen.no';
  static const _pageSize = 1000;

  /// Cached stations — loaded once per app session.
  static List<TollStation>? _cached;

  /// Load all toll stations from NVDB V4.
  static Future<List<TollStation>> loadStations() async {
    if (_cached != null) return _cached!;

    final stations = <TollStation>[];
    String? startParam;
    var page = 0;

    while (page < 10) {
      page++;
      var url = '$_base/vegobjekter/45'
          '?inkluder=egenskaper,lokasjon'
          '&srid=4326'
          '&antall=$_pageSize';
      if (startParam != null) url += '&start=$startParam';

      debugPrint('TollService: fetching page $page ...');
      final resp = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
        'X-Client': 'TourFlow/1.0',
        'X-Kontaktperson': 'post@tourflow.no',
      }).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('TollService: HTTP ${resp.statusCode}, stopping');
        break;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final objects = body['objekter'] as List<dynamic>? ?? [];
      debugPrint('TollService: got ${objects.length} stations on page $page');

      if (objects.isEmpty) break;

      for (final obj in objects) {
        final station = _parseStation(obj as Map<String, dynamic>);
        if (station != null) stations.add(station);
      }

      // Pagination — stop if no next page
      final next = body['metadata']?['neste'];
      if (next == null) break;
      startParam = next['start'] as String?;
      if (startParam == null) break;
    }

    debugPrint('TollService: loaded ${stations.length} stations total');
    _cached = stations;
    return stations;
  }

  static TollStation? _parseStation(Map<String, dynamic> obj) {
    final props = <String, dynamic>{};
    for (final e in (obj['egenskaper'] as List<dynamic>? ?? [])) {
      final m = e as Map<String, dynamic>;
      props[m['navn'] as String] = m['verdi'];
    }

    final wkt = obj['lokasjon']?['geometri']?['wkt'] as String?;
    if (wkt == null) return null;

    // Parse "POINT Z (lat lon elev)" or "POINT (lat lon)"
    final match = RegExp(r'POINT\s*Z?\s*\(\s*([\d.+-]+)\s+([\d.+-]+)')
        .firstMatch(wkt);
    if (match == null) return null;

    final lat = double.tryParse(match.group(1)!);
    final lon = double.tryParse(match.group(2)!);
    if (lat == null || lon == null) return null;

    return TollStation(
      id: obj['id'] as int? ?? 0,
      name: props['Navn bomstasjon'] as String? ?? 'Ukjent',
      lat: lat,
      lon: lon,
      priceCar: (props['Takst liten bil'] as num?)?.toDouble() ?? 0,
      priceCarRush:
          (props['Rushtidstakst liten bil'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Calculate toll for a route given as a list of [lat, lon] coordinate pairs.
  /// [thresholdMeters] is the max distance from the route for a station to count.
  static TollResult calculateTolls(
    List<List<double>> routePoints, {
    double thresholdMeters = 80,
    bool useRushPrice = false,
  }) {
    final stations = _cached ?? [];
    if (stations.isEmpty || routePoints.length < 2) {
      return const TollResult(totalCost: 0, passedStations: []);
    }

    final passed = <TollStation>[];
    final passedIds = <int>{};

    // Sample every N-th point to keep it fast
    final step = max(1, routePoints.length ~/ 500);

    for (var i = 0; i < routePoints.length; i += step) {
      final pLat = routePoints[i][0];
      final pLon = routePoints[i][1];

      for (final s in stations) {
        if (passedIds.contains(s.id)) continue;
        final dist = _haversineMeters(pLat, pLon, s.lat, s.lon);
        if (dist <= thresholdMeters) {
          passed.add(s);
          passedIds.add(s.id);
        }
      }
    }

    final total = passed.fold<double>(
        0, (sum, s) => sum + (useRushPrice ? s.priceCarRush : s.priceCar));

    return TollResult(totalCost: total, passedStations: passed);
  }

  /// Haversine distance in meters.
  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
