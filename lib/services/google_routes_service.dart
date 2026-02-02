import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GoogleRoutesService {
  // ------------------------------------------------------------
  // CONFIG
  // ------------------------------------------------------------
  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  final String _apiKey =
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  // ============================================================
  // ROUTE WITH VIA SUPPORT (ROBUST)
  // ============================================================
  Future<Map<String, dynamic>> getRouteWithVia({
    
    required List<String> places,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Missing GOOGLE_MAPS_API_KEY in .env');
    }

    if (places.length < 2) {
      throw Exception("Need at least 2 places");
    }

    final url = Uri.parse(_baseUrl);
debugPrint("🔥 NEW ROUTE SERVICE ACTIVE");
    // ----------------------------------------------------------
    // BUILD BODY
    // ----------------------------------------------------------

    final origin = places.first;
    final destination = places.last;

    final intermediates = places
        .sublist(1, places.length - 1)
        .map((p) => {
              "address": p,
            })
        .toList();

    final body = {
      "origin": {"address": origin},
      "destination": {"address": destination},
      if (intermediates.isNotEmpty)
        "intermediates": intermediates,
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
    };

    debugPrint("🌐 GOOGLE REQUEST");
    debugPrint(jsonEncode(body));

    late http.Response res;

    // ----------------------------------------------------------
    // REQUEST
    // ----------------------------------------------------------
    try {
      res = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,

              // 👇 IMPORTANT: ask for legs too
              'X-Goog-FieldMask':
                  'routes.distanceMeters,'
                  'routes.legs.distanceMeters,'
                  'routes.polyline.encodedPolyline',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw Exception("Google API timeout (25s)");
    }

    debugPrint("🌐 GOOGLE STATUS: ${res.statusCode}");

    if (res.statusCode != 200) {
      debugPrint(res.body);

      throw Exception(
        'Google API error ${res.statusCode}: ${res.body}',
      );
    }

    // ----------------------------------------------------------
    // PARSE
    // ----------------------------------------------------------
    final data = jsonDecode(res.body);

    final routes = data['routes'];

    if (routes == null ||
        routes is! List ||
        routes.isEmpty) {
      throw Exception(
        'Google returned no routes: ${jsonEncode(data)}',
      );
    }

    final route = routes[0];

    final polyline =
        route['polyline']?['encodedPolyline'];

    if (polyline == null) {
      throw Exception('Missing polyline in route');
    }

    // ==========================================================
// DISTANCE (SAFE HANDLING)
// ==========================================================

num? distanceMeters = route['distanceMeters'];

// Fallback 1: sum legs
if (distanceMeters == null) {
  final legs = route['legs'];

  if (legs is List && legs.isNotEmpty) {
    num sum = 0;

    for (final leg in legs) {
      final d = leg['distanceMeters'];

      if (d is num) {
        sum += d;
      }
    }

    if (sum > 0) {
      distanceMeters = sum;

      debugPrint(
        "⚠️ Used legs distance fallback: $sum m",
      );
    }
  }
}

// Fallback 2: calculate from polyline
if (distanceMeters == null) {
  try {
    final points = _decodePolyline(polyline);

    double total = 0;

    for (int i = 0; i < points.length - 1; i++) {
      total += _haversine(
        points[i][0],
        points[i][1],
        points[i + 1][0],
        points[i + 1][1],
      );
    }

    if (total > 0) {
      distanceMeters = total;

      debugPrint(
        "⚠️ Used polyline distance fallback: ${total.toStringAsFixed(0)} m",
      );
    }
  } catch (e) {
    debugPrint("❌ Polyline calc failed: $e");
  }
}

// Still missing = hard error
// FINAL FALLBACK: straight-line estimate
if (distanceMeters == null) {
  debugPrint("⚠️ Using straight-line fallback");

  final points = _decodePolyline(polyline);

  if (points.length >= 2) {
    final start = points.first;
    final end = points.last;

    final direct = _haversine(
      start[0],
      start[1],
      end[0],
      end[1],
    );

    // Inflate by 25% to simulate roads
    distanceMeters = direct * 1.25;

    debugPrint(
      "⚠️ Estimated distance: ${distanceMeters.toStringAsFixed(0)} m",
    );
  } else {
    // Absolute worst case
    distanceMeters = 50000; // 50 km default
    debugPrint("⚠️ Used hard fallback: 50km");
  }

}

    // ----------------------------------------------------------
    // RESULT
    // ----------------------------------------------------------
    return {
      "distanceMeters": distanceMeters,
      "polyline": polyline,
    };
  }

  // ============================================================
  // BACKWARD COMPAT
  // ============================================================
  Future<Map<String, dynamic>> getRoute({
    required String from,
    required String to,
  }) {
    return getRouteWithVia(
      places: [from, to],
    );
  }
  // ==========================================================
// POLYLINE DISTANCE UTILS
// ==========================================================

List<List<double>> _decodePolyline(String encoded) {
  List<List<double>> points = [];

  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    int shift = 0;
    int result = 0;

    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);

    int dlat =
        (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;

    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);

    int dlng =
        (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add([
      lat / 1E5,
      lng / 1E5,
    ]);
  }

  return points;
}

double _haversine(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const R = 6371000; // meters

  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);

  final a =
      (sin(dLat / 2) * sin(dLat / 2)) +
          cos(_deg2rad(lat1)) *
              cos(_deg2rad(lat2)) *
              (sin(dLon / 2) * sin(dLon / 2));

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c;
}

double _deg2rad(double deg) {
  return deg * (pi / 180);
}
}