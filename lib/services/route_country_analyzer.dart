import 'dart:math';

import 'package:flutter/foundation.dart';

import 'country_service.dart';
import 'polyline_decoder.dart';

class RouteCountryAnalyzer {
  final CountryService _countryService = CountryService();

  /// Hvor ofte vi sampler polyline (jo høyere = raskere, mindre presis)
  /// Web: larger step because Nominatim is rate-limited to 1 req/s
  static const int step = kIsWeb ? 500 : 100;

  /// Maks samtidige API-kall (beskytter deg mot rate-limit)
  /// Web: sequential (Nominatim 1 req/s), desktop: parallel
  static const int maxParallel = kIsWeb ? 1 : 8;

  /// Land vi faktisk bryr oss om
  static const Set<String> vatCountries = {
    'DK',
    'DE',
    'BE',
    'AT',
    'PL',
    'SI',
    'HR',
    'SE',
  };

  double _deg(double d) => d * pi / 180;

  double _distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;

    final dLat = _deg(lat2 - lat1);
    final dLon = _deg(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
            cos(_deg(lat1)) *
                cos(_deg(lat2)) *
                sin(dLon / 2) *
                sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  // =============================================================
  // MAIN — encoded polyline
  // =============================================================
  Future<Map<String, double>> kmPerCountry(
    String encodedPolyline,
  ) async {
    final points = PolylineDecoder.decode(encodedPolyline);
    return _run(points);
  }

  // =============================================================
  // MAIN — raw [lat, lon] list (used on web to avoid polyline
  // encoding/decoding which has bitwise issues in JS)
  // =============================================================
  Future<Map<String, double>> kmPerCountryFromPoints(
    List<List<double>> rawPoints,
  ) async {
    final points = rawPoints
        .map((p) => LatLngPoint(p[0], p[1]))
        .toList();
    return _run(points);
  }

  Future<Map<String, double>> _run(List<LatLngPoint> points) async {
    if (points.length < 2) return {};

    final Map<String, double> result = {};

    final futures = <Future<_SegResult>>[];

    for (int i = 0; i < points.length - 1; i += step) {
      final start = i;
      final end = min(i + step, points.length - 1);

      futures.add(_processSegment(points, start, end));

      // Batch for ikke å drepe API
      if (futures.length >= maxParallel) {
        await _flush(futures, result);
      }
    }

    // Rest
    await _flush(futures, result);

    return result;
  }

  // =============================================================
  // HANDLE ONE SEGMENT
  // Summer alle konsekutive haversines i segmentet — mye mer
  // nøyaktig enn bare endpoint-haversine (straight-line underestimerer)
  // =============================================================
  Future<_SegResult> _processSegment(
    List<LatLngPoint> points,
    int start,
    int end,
  ) async {
    double km = 0;
    for (int j = start; j < end; j++) {
      km += _distance(
        points[j].lat,
        points[j].lng,
        points[j + 1].lat,
        points[j + 1].lng,
      );
    }

    final country =
        await _countryService.getCountry(
      points[start].lat,
      points[start].lng,
    );

    final code = vatCountries.contains(country)
        ? country
        : 'OTHER';

    return _SegResult(code, km);
  }

  // =============================================================
  // FLUSH BATCH
  // =============================================================
  Future<void> _flush(
    List<Future<_SegResult>> futures,
    Map<String, double> result,
  ) async {
    final batch = List.of(futures);
    futures.clear();

    final values = await Future.wait(batch);

    for (final v in values) {
      result[v.country] =
          (result[v.country] ?? 0) + v.km;
    }
  }
}

// =============================================================
// INTERNAL
// =============================================================
class _SegResult {
  final String country;
  final double km;

  _SegResult(this.country, this.km);
}