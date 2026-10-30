import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_env.dart';
import 'country_service.dart';

class GoogleRoutesService {
  // ------------------------------------------------------------
  // CONFIG
  // ------------------------------------------------------------
  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  String get _apiKey => AppEnv.googleMapsApiKey;

  final CountryService _country = CountryService();

  // ============================================================
  // Geocoding via the `geocode` edge function + OSRM routing.
  //
  // Geocoding used to go straight to Nominatim from the client, but its
  // 1 req/sec limit is per IP: a few route lookups from one office earn the
  // whole IP a 429 that sticks, and every route then came back empty
  // ("Route cached (no map)"). The edge function uses Google Geocoding, which
  // has no such limit and keeps the key server-side. OSRM is fine from the
  // client — it is only the geocoding step that was rate-limited.
  // ============================================================

  /// Geocode every place in one round trip → [lat, lon] per place.
  Future<List<List<double>>> _geocodeAll(List<String> places) async {
    final res = await Supabase.instance.client.functions
        .invoke('geocode', body: {'places': places})
        .timeout(const Duration(seconds: 30));

    final data = res.data;
    final raw = data is Map ? data['coords'] as List? : null;

    if (raw == null || raw.length != places.length) {
      throw Exception('Geocoding failed for ${places.join(", ")}');
    }

    final coords = <List<double>>[];

    for (int i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c is! List || c.length < 2) {
        throw Exception('Could not geocode: "${places[i]}"');
      }
      coords.add([
        (c[0] as num).toDouble(),
        (c[1] as num).toDouble(),
      ]);
    }

    return coords;
  }

  Future<Map<String, dynamic>> _routeForCoords(
    List<List<double>> coords,
  ) async {
    // OSRM expects lon,lat pairs separated by semicolons
    final coordStr = coords.map((c) => '${c[1]},${c[0]}').join(';');

    // Use geojson — gives plain [lon,lat] coordinates, no decoding issues.
    // steps=true so we can detect ferry segments (mode == "ferry").
    final osrmUrl = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordStr'
      '?overview=full&alternatives=true&geometries=geojson&steps=true',
    );

    debugPrint('🚗 OSRM: $osrmUrl');

    final res = await http
        .get(osrmUrl, headers: {
          'User-Agent': 'TourFlow/1.0 (tourflow-booking)',
        })
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('OSRM error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') {
      throw Exception('OSRM: ${data['code']} — ${data['message'] ?? ''}');
    }

    final routes = data['routes'] as List;
    final List<Map<String, dynamic>> parsedRoutes = [];

    for (final route in routes) {
      // GeoJSON geometry: { "type": "LineString", "coordinates": [[lon,lat], ...] }
      final geometry = route['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final rawCoords = geometry['coordinates'] as List?;
      if (rawCoords == null || rawCoords.isEmpty) continue;

      // GeoJSON uses [lon, lat] — store as [lat, lon] raw points, no encoding
      final latLonPoints = rawCoords
          .map((c) => [
                (c[1] as num).toDouble(), // lat
                (c[0] as num).toDouble(), // lon
              ])
          .toList();

      final distanceMeters = route['distance'] as num;

      // ----------------------------------------------------------
      // FERRY DETECTION via OSRM steps (mode == "ferry")
      // ----------------------------------------------------------
      bool hasFerrySteps = false;
      final List<String> ferryNames = [];

      final legs = route['legs'];
      if (legs is List) {
        for (final leg in legs) {
          final steps = leg['steps'];
          if (steps is! List) continue;
          for (final step in steps) {
            if (step is! Map) continue;
            if (step['mode'] == 'ferry') {
              hasFerrySteps = true;
              final n = step['name'] as String?;
              if (n != null && n.isNotEmpty && !ferryNames.contains(n)) {
                ferryNames.add(n);
              }
            }
          }
        }
      }
      debugPrint('⛴️ OSRM ferry: hasFerry=$hasFerrySteps, names=$ferryNames');

      parsedRoutes.add({
        'distanceMeters': distanceMeters,
        'rawPoints': latLonPoints, // List of [lat, lon]
        'hasFerrySteps': hasFerrySteps,
        'ferryNames': ferryNames,
      });
    }

    if (parsedRoutes.isEmpty) throw Exception('OSRM returned no routes');

    debugPrint('✅ OSRM: ${parsedRoutes.length} route(s) found');
    return {'routes': parsedRoutes};
  }


  // ============================================================
  // ROUTE WITH VIA + ALTERNATIVES
  // ============================================================
  /// E6 through Norway, south → north. Left to itself OSRM sends Oslo → Alta
  /// across Sweden and Finland (1131 km SE + 190 km FI, against 405 km in
  /// Norway); pinning these waypoints keeps the whole leg on Norwegian roads
  /// for about 170 km more. Svinesund is the border crossing, so a leg coming
  /// up from the continent enters Norway there rather than further north.
  static const List<List<double>> _norwegianCorridor = [
    [59.0950, 11.2680], // Svinesund
    [59.9139, 10.7522], // Oslo
    [61.1153, 10.4663], // Lillehammer
    [62.0748, 9.1233], // Dombås
    [63.4305, 10.3951], // Trondheim
    [64.0149, 11.4951], // Steinkjer
    [65.8373, 13.1928], // Mosjøen
    [66.3128, 14.1424], // Mo i Rana
    [67.2596, 15.3928], // Fauske
    [68.4385, 17.4272], // Narvik
    [69.2186, 19.5500], // Nordkjosbotn
  ];

  /// Splices the corridor points that sit between each consecutive pair of
  /// waypoints, in the direction of travel.
  List<List<double>> _withCorridor(List<List<double>> coords) {
    final out = <List<double>>[];

    for (int i = 0; i < coords.length - 1; i++) {
      final a = coords[i];
      final b = coords[i + 1];

      out.add(a);

      final lo = min(a[0], b[0]);
      final hi = max(a[0], b[0]);

      final between =
          _norwegianCorridor.where((p) => p[0] > lo && p[0] < hi).toList();

      if (a[0] > b[0]) {
        between.sort((x, y) => y[0].compareTo(x[0]));
      }

      out.addAll(between);
    }

    out.add(coords.last);
    return out;
  }

  double _haversineKm(List<double> a, List<double> b) {
    const r = 6371.0;
    final dLat = (b[0] - a[0]) * pi / 180;
    final dLon = (b[1] - a[1]) * pi / 180;

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(a[0] * pi / 180) *
            cos(b[0] * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);

    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  /// Km of the route's first alternative that falls outside Norway. A sample
  /// we cannot place counts as domestic, so a failed lookup never pushes the
  /// choice towards the detour.
  Future<double> _foreignKm(Map<String, dynamic> result) async {
    final routes = List<Map<String, dynamic>>.from(result['routes'] ?? []);
    if (routes.isEmpty) return double.infinity;

    final raw = routes.first['rawPoints'] as List?;
    if (raw == null || raw.isEmpty) return double.infinity;

    final pts = raw.map<List<double>>((p) {
      final pair = p as List;
      return [
        (pair[0] as num).toDouble(),
        (pair[1] as num).toDouble(),
      ];
    }).toList();

    const step = 500;
    final segmentKm = <double>[];
    final samples = <List<double>>[];

    for (int i = 0; i < pts.length - 1; i += step) {
      final end = min(i + step, pts.length - 1);

      double km = 0;
      for (int j = i; j < end; j++) {
        km += _haversineKm(pts[j], pts[j + 1]);
      }

      segmentKm.add(km);
      samples.add(pts[i]);
    }

    final countries = await _country.getCountries(samples);

    double foreign = 0;
    for (int i = 0; i < segmentKm.length; i++) {
      final c = i < countries.length ? countries[i] : 'Unknown';
      if (c != 'NO' && c != 'Unknown') foreign += segmentKm[i];
    }

    return foreign;
  }

  Future<Map<String, dynamic>> getRouteWithVia({
    required List<String> places,
    bool keepInsideNorway = false,
  }) async {
    debugPrint('🌍 ROUTE: geocode edge fn + OSRM for ${places.length} places');

    final coords = await _geocodeAll(places);

    for (int i = 0; i < places.length; i++) {
      debugPrint('  📍 ${places[i]} → ${coords[i]}');
    }

    final direct = await _routeForCoords(coords);

    if (!keepInsideNorway) return direct;

    final corridorCoords = _withCorridor(coords);

    // Nothing of the corridor lies between these points — the detour cannot
    // help, so don't pay for a second lookup.
    if (corridorCoords.length == coords.length) return direct;

    try {
      final corridor = await _routeForCoords(corridorCoords);

      final foreign = await Future.wait([
        _foreignKm(direct),
        _foreignKm(corridor),
      ]);

      debugPrint('🇳🇴 outside Norway — direct: ${foreign[0].round()} km, '
          'corridor: ${foreign[1].round()} km');

      // Equal means the corridor bought nothing, and it is always the longer
      // of the two, so only take it when it genuinely cuts foreign km.
      if (foreign[1] < foreign[0]) return corridor;
    } catch (e) {
      debugPrint('Norway corridor failed, keeping the direct route: $e');
    }

    return direct;
  }

  // ============================================================
  // GOOGLE ROUTES API (preserved fallback — billing required)
  // ============================================================
  // ignore: unused_element
  Future<Map<String, dynamic>> _getRouteGoogle({
    required List<String> places,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Missing GOOGLE_MAPS_API_KEY in .env');
    }

    if (places.length < 2) {
      throw Exception("Need at least 2 places");
    }

    final url = Uri.parse(_baseUrl);

    debugPrint("🔥 GOOGLE ROUTES (MULTI)");

    // ----------------------------------------------------------
    // BUILD BODY
    // ----------------------------------------------------------

    final origin = places.first;
    final destination = places.last;

    final intermediates = places
        .sublist(1, places.length - 1)
        .map((p) => {"address": p})
        .toList();

    final body = {
      "origin": {"address": origin},
      "destination": {"address": destination},

      if (intermediates.isNotEmpty)
        "intermediates": intermediates,

      "travelMode": "DRIVE",

      // Request multiple routes
      "computeAlternativeRoutes": true,

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

              // Ask only what we need
              'X-Goog-FieldMask':
                  'routes.distanceMeters,'
                  'routes.legs.distanceMeters,'
                  'routes.legs.steps.travelMode,'
                  'routes.legs.steps.navigationInstruction,'
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

    // ----------------------------------------------------------
    // PARSE ALL ROUTES
    // ----------------------------------------------------------

    final List<Map<String, dynamic>> parsedRoutes = [];

    for (final route in routes) {
      final polyline =
          route['polyline']?['encodedPolyline'];

      if (polyline == null) continue;

      num? distanceMeters = route['distanceMeters'];

      // ==================================================
      // DISTANCE FALLBACKS
      // ==================================================

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
          }
        } catch (_) {}
      }

      // Fallback 3: straight-line estimate
      if (distanceMeters == null) {
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

          // Inflate to simulate roads
          distanceMeters = direct * 1.25;
        } else {
          distanceMeters = 50000; // 50km hard fallback
        }
      }

      // --------------------------------------------------
      // DETECT FERRY STEPS
      // --------------------------------------------------
      bool hasFerrySteps = false;
      final List<String> ferryNames = [];

      final ferryLegs = route['legs'];
      if (ferryLegs is List) {
        for (final leg in ferryLegs) {
          final steps = leg['steps'];
          if (steps is! List) continue;
          for (final step in steps) {
            final maneuver =
                (step['navigationInstruction']?['maneuver'] as String? ?? '')
                    .toUpperCase();
            final isFerry = maneuver == 'FERRY' ||
                maneuver == 'FERRY_BOAT' ||
                maneuver == 'FERRY_TRAIN' ||
                step['travelMode'] == 'FERRY';
            if (isFerry) {
              hasFerrySteps = true;
              final instr =
                  step['navigationInstruction']?['instructions'] as String?;
              if (instr != null && instr.isNotEmpty && !ferryNames.contains(instr)) {
                ferryNames.add(instr);
              }
            }
          }
        }
      }
      debugPrint('⛴️ Ferry detection: hasFerry=$hasFerrySteps, names=$ferryNames');

      parsedRoutes.add({
        "distanceMeters": distanceMeters,
        "polyline": polyline,
        "hasFerrySteps": hasFerrySteps,
        "ferryNames": ferryNames,
      });
    }

    if (parsedRoutes.isEmpty) {
      throw Exception("No valid routes returned");
    }

    // ----------------------------------------------------------
    // RESULT (MULTI)
    // ----------------------------------------------------------
    return {
      "routes": parsedRoutes,
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

  // ============================================================
  // POLYLINE UTILS
  // ============================================================

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
        sin(dLat / 2) * sin(dLat / 2) +
            cos(_deg2rad(lat1)) *
                cos(_deg2rad(lat2)) *
                sin(dLon / 2) *
                sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  double _deg2rad(double deg) {
    return deg * (pi / 180);
  }
}