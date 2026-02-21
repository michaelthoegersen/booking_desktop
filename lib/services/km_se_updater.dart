import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Automatically populates [km_se] in routes_all by:
///   1. Geocoding from/to with Nominatim (free OSM, no key needed)
///   2. Fetching route geometry from OSRM (free, no key needed)
///   3. Summing segment distances where the midpoint lies in Sweden
///   4. Writing the result back to Supabase
class KmSeUpdater {
  static const _nominatim = 'https://nominatim.openstreetmap.org/search';
  static const _osrm = 'https://router.project-osrm.org/route/v1/driving';

  // -----------------------------------------------------------------------
  // PUBLIC ENTRY POINT
  // -----------------------------------------------------------------------

  /// Iterates all routes_all rows where km_se IS NULL and fills them in.
  /// [onProgress] is called with status messages (can update UI).
  /// [onError]    is called with soft errors (individual route failures).
  /// Returns the number of routes successfully updated.
  static Future<int> updateAll({
    required void Function(String msg) onProgress,
    required void Function(String msg) onError,
  }) async {
    final client = Supabase.instance.client;

    // Fetch routes that still need km_se (NULL) OR that are Norway-only but
    // were incorrectly set to a value > 0 (old bug — re-process them to 0).
    final nullRows = await client
        .from('routes_all')
        .select('id, from_place, to_place')
        .isFilter('km_se', null) as List;

    // Also fetch rows where km_se > 0 so we can re-check if they are
    // actually Norwegian-only routes that were miscalculated earlier.
    final nonZeroRows = await client
        .from('routes_all')
        .select('id, from_place, to_place, km_se')
        .gt('km_se', 0) as List;

    final rows = [...nullRows, ...nonZeroRows];

    if (rows.isEmpty) {
      onProgress('Alle ruter er allerede oppdatert.');
      return 0;
    }

    onProgress('Fant ${nullRows.length} ruter uten km_se og '
        '${nonZeroRows.length} ruter med km_se > 0 (sjekker om noen er norske)...');
    int updated = 0;

    for (int i = 0; i < rows.length; i++) {
      final id    = rows[i]['id'];
      final from  = (rows[i]['from_place'] as String).trim();
      final to    = (rows[i]['to_place']   as String).trim();

      onProgress('[${i + 1}/${rows.length}] $from → $to');

      // Geocode both endpoints
      final fromGeo = await _geocode(from);
      if (fromGeo == null) { onError('  ✗ Fant ikke koordinater: $from'); continue; }

      final toGeo = await _geocode(to);
      if (toGeo == null) { onError('  ✗ Fant ikke koordinater: $to'); continue; }

      // If both endpoints are in Norway there can be no Swedish km
      final bothInNorway = fromGeo.country == 'no' && toGeo.country == 'no';
      double sweKm;
      if (bothInNorway) {
        sweKm = 0.0;
        onProgress('  → Innenlands norsk rute — km_se = 0');
      } else {
        final computed = await _computeSweKm(fromGeo.coords, toGeo.coords);
        if (computed == null) { onError('  ✗ Ruting feilet: $from → $to'); continue; }
        sweKm = computed;
      }

      // For rows that already had km_se set, only write if the value changes
      final existingKmSe = rows[i]['km_se'];
      if (existingKmSe != null) {
        final existingVal = (existingKmSe as num).toDouble();
        if ((existingVal - sweKm).abs() < 0.5) {
          onProgress('  = Ingen endring (${sweKm.toStringAsFixed(0)} km)');
          continue;
        }
        onProgress('  ↻ Korrigerer ${existingVal.toStringAsFixed(0)} → ${sweKm.toStringAsFixed(0)} km');
      }

      // Write to database
      await client
          .from('routes_all')
          .update({'km_se': sweKm})
          .eq('id', id);

      updated++;
      onProgress('  ✓ km_se = ${sweKm.toStringAsFixed(0)} km');
    }

    onProgress('Ferdig! $updated av ${rows.length} ruter oppdatert.');
    return updated;
  }

  // -----------------------------------------------------------------------
  // SINGLE-ROUTE HELPER
  // -----------------------------------------------------------------------

  /// Geocodes [from]/[to], computes Swedish km via OSRM, and writes it to
  /// `routes_all` for the row with the given [id].
  /// Returns the computed sweKm on success, null on any failure.
  static Future<double?> computeAndSaveOne({
    required String id,
    required String from,
    required String to,
  }) async {
    final fromGeo = await _geocode(from);
    if (fromGeo == null) return null;

    final toGeo = await _geocode(to);
    if (toGeo == null) return null;

    final double sweKm;
    if (fromGeo.country == 'no' && toGeo.country == 'no') {
      sweKm = 0.0;
    } else {
      final computed = await _computeSweKm(fromGeo.coords, toGeo.coords);
      if (computed == null) return null;
      sweKm = computed;
    }

    await Supabase.instance.client
        .from('routes_all')
        .update({'km_se': sweKm})
        .eq('id', id);

    return sweKm;
  }

  // -----------------------------------------------------------------------
  // GEOCODING — Nominatim (OSM, free, 1 req/s rate limit)
  // -----------------------------------------------------------------------

  /// Result type carrying coordinates and the two-letter country code.
  static ({List<double> coords, String country})? _makeGeo(
          List<double> coords, String country) =>
      (coords: coords, country: country);

  /// Returns coords + country code, or null on failure.
  static Future<({List<double> coords, String country})?> _geocode(
      String place) async {
    // Respect Nominatim's 1 req/s policy
    await Future.delayed(const Duration(milliseconds: 1200));

    try {
      final uri = Uri.parse(_nominatim).replace(queryParameters: {
        'q': place,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'no,se,dk,de,be,pl,at,hr,si,gb,fr,es,it,nl,pt,ch,cz,sk,hu,ro',
      });

      final resp = await http
          .get(uri, headers: {'User-Agent': 'TourFlow-KmSe-Updater/1.0'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as List;
      if (data.isEmpty) return null;

      final lat     = double.parse(data[0]['lat'] as String);
      final lon     = double.parse(data[0]['lon'] as String);
      final country = (data[0]['country_code'] as String?)?.toLowerCase() ?? '';

      return _makeGeo([lat, lon], country);
    } catch (e) {
      debugPrint('[KmSeUpdater] geocode error for "$place": $e');
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // ROUTING — OSRM public server (free, no key)
  // -----------------------------------------------------------------------

  /// Returns Swedish km along the route, or null on failure.
  static Future<double?> _computeSweKm(
    List<double> from,
    List<double> to,
  ) async {
    try {
      // OSRM: /route/v1/driving/{fromLon},{fromLat};{toLon},{toLat}
      final url =
          '$_osrm/${from[1]},${from[0]};${to[1]},${to[0]}'
          '?overview=full&geometries=geojson';

      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      // GeoJSON coords: [[lon, lat], [lon, lat], ...]
      final raw = (data['routes'][0]['geometry']['coordinates'] as List)
          .cast<List<dynamic>>();

      // Convert to [lat, lon] pairs
      final coords = raw
          .map((c) => [
                (c[1] as num).toDouble(), // lat
                (c[0] as num).toDouble(), // lon
              ])
          .toList();

      double sweKm = 0.0;
      for (int i = 0; i + 1 < coords.length; i++) {
        final lat1 = coords[i][0],    lon1 = coords[i][1];
        final lat2 = coords[i + 1][0], lon2 = coords[i + 1][1];
        final midLat = (lat1 + lat2) / 2;
        final midLon = (lon1 + lon2) / 2;
        if (_isInSweden(midLat, midLon)) {
          sweKm += _haversineKm(lat1, lon1, lat2, lon2);
        }
      }

      return double.parse(sweKm.toStringAsFixed(1));
    } catch (e) {
      debugPrint('[KmSeUpdater] routing error: $e');
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // SWEDEN DETECTION (approximate polygon)
  // -----------------------------------------------------------------------

  /// Returns true if [lat, lon] is approximately inside Sweden.
  ///
  /// Uses a piecewise longitude threshold per latitude band, approximating the
  /// Norway-Sweden border and excluding Denmark. Good enough for road routing.
  static bool _isInSweden(double lat, double lon) {
    // Fast bounding-box rejection (Sweden bounding box)
    if (lat < 55.2 || lat > 69.5) return false;
    if (lon < 10.9 || lon > 24.2) return false;

    // Sweden's northernmost point is Treriksröset at 69.07°N, 20.55°E.
    // Anything above this latitude is Norway or Finland — never Sweden.
    if (lat > 69.07) return false;

    // Far north (68–69.07°N): Sweden occupies a narrow strip.
    // Norway-Sweden border is ~18°E here; Finland starts ~20.6°E.
    // Riksgränsen (Sweden) 68.43°N, 18.13°E — correctly inside.
    // Narvik (Norway)       68.44°N, 17.43°E — correctly outside.
    if (lat >= 68.0) return lon >= 18.0 && lon <= 20.6;

    // Northern Sweden (65–68°N): border ~14.5°E
    if (lat >= 65.0) return lon >= 14.5;

    // Central-north (62–65°N): border ~12.5°E
    if (lat >= 62.0) return lon >= 12.5;

    // Central (60–62°N): border ~11.8°E
    if (lat >= 60.0) return lon >= 11.8;

    // Approaching Oslo / Østfold (59–60°N): border shifts east to ~11.5°E.
    // Askim (59.58°N, 11.17°E) and Lillestrøm (59.95°N, 11.04°E) → NOT Sweden.
    if (lat >= 59.0) return lon >= 11.5;

    // Strömstad / Bohuslen (58.5–59°N): Swedish coast starts ~11.1°E.
    // Strömstad (Sweden) 58.94°N, 11.17°E → correctly inside.
    if (lat >= 58.5) return lon >= 11.1;

    // Mid-Scandinavia (57–58.5°N): Gothenburg (57.7°N, 11.97°E) → inside.
    if (lat >= 57.0) return lon >= 11.0;

    // Southern Scandinavia (55.4–57°N): Exclude Zealand / Funen (Denmark).
    // Sweden's Scania begins east of the Øresund at ~12.6°E.
    // Copenhagen (Denmark) 55.68°N, 12.57°E → NOT Sweden.
    // Helsingborg (Sweden) 56.05°N, 12.69°E → correctly inside.
    // Malmö (Sweden)       55.60°N, 13.00°E → correctly inside.
    if (lat >= 55.4) return lon >= 12.6;

    // Below 55.4°N: Denmark / German Bight — never Sweden.
    return false;
  }

  // -----------------------------------------------------------------------
  // HAVERSINE DISTANCE
  // -----------------------------------------------------------------------

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
