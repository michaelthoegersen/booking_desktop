import 'dart:math';

import 'package:flutter/foundation.dart';

import 'country_service.dart';
import 'polyline_decoder.dart';

class RouteCountryAnalyzer {
  final CountryService _countryService = CountryService();

  /// Hvor ofte vi sampler polyline (jo høyere = raskere, mindre presis).
  /// Web sampler grovere enn desktop — uendret fra før, så tallene ikke
  /// flytter seg av denne fiksen.
  static const int step = kIsWeb ? 500 : 100;

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

    // One sample per segment, then ONE batched country lookup. The old version
    // fired a request per segment, which is exactly what got rate-limited.
    final segmentKm = <double>[];
    final samples = <List<double>>[];

    for (int i = 0; i < points.length - 1; i += step) {
      final end = min(i + step, points.length - 1);

      // Sum every consecutive haversine in the segment — far more accurate
      // than a single endpoint-to-endpoint line, which underestimates.
      double km = 0;
      for (int j = i; j < end; j++) {
        km += _distance(
          points[j].lat,
          points[j].lng,
          points[j + 1].lat,
          points[j + 1].lng,
        );
      }

      segmentKm.add(km);
      samples.add([points[i].lat, points[i].lng]);
    }

    final countries = await _countryService.getCountries(samples);

    final Map<String, double> result = {};

    for (int i = 0; i < segmentKm.length; i++) {
      final country = i < countries.length ? countries[i] : 'Unknown';

      final code = vatCountries.contains(country) ? country : 'OTHER';

      result[code] = (result[code] ?? 0) + segmentKm[i];
    }

    return result;
  }
}
