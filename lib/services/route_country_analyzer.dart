import 'dart:math';

import 'country_service.dart';
import 'polyline_decoder.dart';

class RouteCountryAnalyzer {
  final CountryService _countryService = CountryService();

  /// Hvor ofte vi sampler polyline (jo høyere = raskere, mindre presis)
  static const int step = 100;

  /// Maks samtidige API-kall (beskytter deg mot rate-limit)
  static const int maxParallel = 8;

  /// Land vi faktisk bryr oss om
  static const Set<String> vatCountries = {
    'DK',
    'DE',
    'BE',
    'AT',
    'PL',
    'SI',
    'HR',
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
  // MAIN
  // =============================================================
  Future<Map<String, double>> kmPerCountry(
    String encodedPolyline,
  ) async {
    final points =
        PolylineDecoder.decode(encodedPolyline);

    if (points.length < 2) return {};

    final Map<String, double> result = {};

    final futures = <Future<_SegResult>>[];

    for (int i = 0; i < points.length - 1; i += step) {
      final p1 = points[i];
      final p2 = points[
          min(i + step, points.length - 1)];

      futures.add(_processSegment(p1, p2));

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
  // =============================================================
  Future<_SegResult> _processSegment(
    LatLngPoint p1,
    LatLngPoint p2,
  ) async {
    final km = _distance(
      p1.lat,
      p1.lng,
      p2.lat,
      p2.lng,
    );

    final country =
        await _countryService.getCountry(
      p1.lat,
      p1.lng,
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