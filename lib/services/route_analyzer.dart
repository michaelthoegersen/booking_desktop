import 'dart:math';

import 'package:flutter/foundation.dart';

import 'country_service.dart';
import 'polyline_decoder.dart';

class RouteAnalyzer {
  final _countryService = CountryService();

  // ---------------------------------------------
  // LAND MED MOMS
  // ---------------------------------------------
  static const Set<String> _vatCountries = {
    "Denmark",   // DK
    "Germany",   // DE
    "Austria",   // AT
    "Poland",    // PL
    "Belgium",   // BE
    "Slovenia",  // SI
    "Croatia",   // HR
  };

  // ---------------------------------------------
  // HAVERSINE
  // ---------------------------------------------
  double _distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // km

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

  double _deg(double d) => d * pi / 180;

  // ---------------------------------------------
  // MAIN
  // ---------------------------------------------
  Future<RouteAnalysisResult> kmPerCountry(
    String polyline, {
    required double googleKm,
  }) async {
    final points = PolylineDecoder.decode(polyline);

    debugPrint("🔎 Total points: ${points.length}");

    // 👉 Sampling
    const int step = 100;

    double rawTotalKm = 0;

    final Map<String, double> result = {};

    for (int i = 0; i < points.length - 1; i += step) {
      final p1 = points[i];

      final nextIndex =
          (i + step < points.length)
              ? i + step
              : points.length - 1;

      final p2 = points[nextIndex];

      final km = _distance(
        p1.lat,
        p1.lng,
        p2.lat,
        p2.lng,
      );

      rawTotalKm += km;

      // ---------------------------------------------
      // LAND
      // ---------------------------------------------
      final country =
          await _countryService.getCountry(
        p1.lat,
        p1.lng,
      );

      // 👉 Kun moms-land
      if (_vatCountries.contains(country)) {
        result[country] =
            (result[country] ?? 0) + km;
      }

      if (i % 500 == 0) {
        debugPrint("⏳ Processed $i points");
      }
    }

    // ---------------------------------------------
    // SCALE TO GOOGLE
    // ---------------------------------------------
    final scale =
        rawTotalKm == 0 ? 1 : googleKm / rawTotalKm;

    debugPrint("📐 Scale factor: $scale");

    final scaledResult = <String, double>{};

    result.forEach((c, km) {
      scaledResult[c] = km * scale;
    });

    final finalTotal = rawTotalKm * scale;

    debugPrint("✅ Analysis finished");
    debugPrint("📏 Raw km: $rawTotalKm");
    debugPrint("📏 Google km: $googleKm");
    debugPrint("📏 Final km: $finalTotal");

    debugPrint("📊 VAT COUNTRIES RESULT:");
    scaledResult.forEach((c, km) {
      debugPrint("   $c: ${km.toStringAsFixed(1)} km");
    });

    return RouteAnalysisResult(
      totalKm: finalTotal,
      perCountry: scaledResult,
      points: points.length,
    );
  }
}

// ---------------------------------------------
// RESULT MODEL
// ---------------------------------------------
class RouteAnalysisResult {
  final double totalKm;
  final Map<String, double> perCountry;
  final int points;

  RouteAnalysisResult({
    required this.totalKm,
    required this.perCountry,
    required this.points,
  });
}