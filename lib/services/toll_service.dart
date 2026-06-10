import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which NVDB price class to use when summing toll station costs.
/// - [car]   Takst liten bil (vehicles ≤ 3500 kg)
/// - [truck] Takst stor bil  (vehicles > 3500 kg — incl. lastebil/buss)
enum TollVehicleClass { car, truck }

/// A single toll station with coordinates and prices.
class TollStation {
  final int id;
  final String name;
  final double lat;
  final double lon;
  final double priceCar;
  final double priceCarRush;
  final double priceTruck;
  final double priceTruckRush;

  const TollStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.priceCar,
    required this.priceCarRush,
    required this.priceTruck,
    required this.priceTruckRush,
  });

  double priceFor(TollVehicleClass vc, {bool rush = false}) {
    switch (vc) {
      case TollVehicleClass.car:
        return rush ? priceCarRush : priceCar;
      case TollVehicleClass.truck:
        // Fall back to small-car price if NVDB has no large-vehicle rate
        // for this station (a few private toll roads only publish one).
        final t = rush ? priceTruckRush : priceTruck;
        if (t > 0) return t;
        return rush ? priceCarRush : priceCar;
    }
  }
}

/// Result of toll calculation for a route.
class TollResult {
  final double totalCost;
  final List<TollStation> passedStations;

  const TollResult({required this.totalCost, required this.passedStations});
}

/// Service that loads Norwegian toll stations (via the `toll-stations` Supabase
/// Edge Function, which proxies NVDB server-side to avoid browser CORS) and
/// matches them against a route polyline to calculate toll costs.
class TollService {
  /// Cached stations — loaded once per app session.
  static List<TollStation>? _cached;

  /// Load all toll stations via the `toll-stations` edge function.
  ///
  /// NVDB cannot be called directly from the browser (no CORS), so the fetch +
  /// parse happens server-side; here we just deserialize the slim station list.
  static Future<List<TollStation>> loadStations() async {
    if (_cached != null) return _cached!;

    try {
      final resp = await Supabase.instance.client.functions
          .invoke('toll-stations')
          .timeout(const Duration(seconds: 30));

      final data = resp.data;
      final list = (data is Map ? data['stations'] : null) as List? ?? [];

      final stations = <TollStation>[];
      for (final s in list) {
        final m = (s as Map).cast<String, dynamic>();
        stations.add(TollStation(
          id: (m['id'] as num?)?.toInt() ?? 0,
          name: m['name'] as String? ?? 'Ukjent',
          lat: (m['lat'] as num?)?.toDouble() ?? 0,
          lon: (m['lon'] as num?)?.toDouble() ?? 0,
          priceCar: (m['priceCar'] as num?)?.toDouble() ?? 0,
          priceCarRush: (m['priceCarRush'] as num?)?.toDouble() ?? 0,
          priceTruck: (m['priceTruck'] as num?)?.toDouble() ?? 0,
          priceTruckRush: (m['priceTruckRush'] as num?)?.toDouble() ?? 0,
        ));
      }

      debugPrint('TollService: loaded ${stations.length} stations via edge function');
      _cached = stations;
      return stations;
    } catch (e) {
      debugPrint('TollService: loadStations failed: $e');
      _cached = [];
      return [];
    }
  }

  /// Calculate toll for a route given as a list of [lat, lon] coordinate pairs.
  /// [thresholdMeters] is the max distance from the route for a station to count.
  /// [vehicleClass] selects which NVDB tariff to sum (car vs. truck/large).
  static TollResult calculateTolls(
    List<List<double>> routePoints, {
    double thresholdMeters = 50,
    bool useRushPrice = false,
    TollVehicleClass vehicleClass = TollVehicleClass.car,
  }) {
    final stations = _cached ?? [];
    if (stations.isEmpty || routePoints.length < 2) {
      return const TollResult(totalCost: 0, passedStations: []);
    }

    // Tight threshold (30m): only matches stations directly on the road
    // being driven, not on nearby ramps or parallel roads.
    //
    // Geo-dedup (300m): NVDB has multiple objects per physical station
    // (per lane/direction). These are < 100m apart. Separate toll stations
    // are always > 500m apart even in cities.
    const geoDedupMeters = 300.0;

    final passed = <TollStation>[];

    // Sample every N-th point to keep it fast
    const step = 1; // check every point — accuracy over speed

    for (var i = 0; i < routePoints.length; i += step) {
      final pLat = routePoints[i][0];
      final pLon = routePoints[i][1];

      for (final s in stations) {
        final dist = _haversineMeters(pLat, pLon, s.lat, s.lon);
        if (dist > thresholdMeters) continue;

        // Skip if too close to an already-matched station (same bomsnitt)
        final isDuplicate = passed.any((p) =>
            _haversineMeters(p.lat, p.lon, s.lat, s.lon) < geoDedupMeters);
        if (isDuplicate) continue;

        passed.add(s);
      }
    }

    final total = passed.fold<double>(
        0,
        (sum, s) =>
            sum + s.priceFor(vehicleClass, rush: useRushPrice));

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
