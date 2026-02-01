import 'dart:math';

import 'country_service.dart';
import 'polyline_decoder.dart';

class RouteCountryAnalyzer {
  final CountryService _countryService =
      CountryService();

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

  // ------------------------------------------------------------
  Future<Map<String, double>> kmPerCountry(
    String encodedPolyline,
  ) async {
    final points =
        PolylineDecoder.decode(encodedPolyline);

    final Map<String, double> result = {};

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      final km = _distance(
        p1[0],
        p1[1],
        p2[0],
        p2[1],
      );

      final country =
          await _countryService.getCountry(
        p1[0],
        p1[1],
      );

      result[country] =
          (result[country] ?? 0) + km;
    }

    return result;
  }
}