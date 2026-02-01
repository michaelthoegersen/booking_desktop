import 'dart:async';
import 'dart:convert';

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

  // ------------------------------------------------------------
  // GET ROUTE
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> getRoute({
    required String from,
    required String to,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'Missing GOOGLE_MAPS_API_KEY in .env',
      );
    }

    final url = Uri.parse(_baseUrl);

    // ----------------------------------------------------------
    // BODY
    // ----------------------------------------------------------
    final body = {
      "origin": {"address": from},
      "destination": {"address": to},
      "travelMode": "DRIVE",
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

              // 👇 Viktig: bare det vi trenger
              'X-Goog-FieldMask':
                  'routes.distanceMeters,'
                  'routes.polyline.encodedPolyline',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 20),
          );
    } on TimeoutException {
      throw Exception(
        "Google API timeout (20s)",
      );
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

    final distanceMeters =
        route['distanceMeters'];

    final polyline =
        route['polyline']?['encodedPolyline'];

    if (distanceMeters == null) {
      throw Exception(
        'Missing distanceMeters in route',
      );
    }

    if (polyline == null) {
      throw Exception(
        'Missing polyline in route',
      );
    }

    debugPrint("✅ ROUTE OK");
    debugPrint("   Distance: $distanceMeters m");
    debugPrint("   Polyline: ${polyline.length} chars");

    // ----------------------------------------------------------
    // RESULT
    // ----------------------------------------------------------
    return {
      "distanceMeters": distanceMeters,
      "polyline": polyline,
    };
  }
}