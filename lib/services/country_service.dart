import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Coordinate → country code, via the `geocode` edge function.
///
/// This used to call Nominatim straight from the client, one request per
/// sampled point. Nominatim allows 1 request/sec per IP, so a couple of route
/// analyses got the whole office IP a 429 that stuck — every lookup then
/// returned 'Unknown' and country km silently came out empty. The edge
/// function uses BigDataCloud (free, no key) with Google as fallback, and
/// takes every point in one round trip.
class CountryService {
  final Map<String, String> _cache = {};

  String _key(double lat, double lng) {
    final la = (lat * 50).round() / 50;
    final ln = (lng * 50).round() / 50;
    return "$la,$ln";
  }

  Future<String> getCountry(double lat, double lng) async {
    final countries = await getCountries([
      [lat, lng],
    ]);
    return countries.isEmpty ? 'Unknown' : countries.first;
  }

  /// Country code per point, in the order given. A point that cannot be
  /// resolved comes back as 'Unknown' rather than failing the batch.
  Future<List<String>> getCountries(List<List<double>> points) async {
    if (points.isEmpty) return [];

    final result = List<String>.filled(points.length, 'Unknown');
    final missing = <int>[];

    for (int i = 0; i < points.length; i++) {
      final cached = _cache[_key(points[i][0], points[i][1])];
      if (cached != null) {
        result[i] = cached;
      } else {
        missing.add(i);
      }
    }

    if (missing.isEmpty) return result;

    try {
      final res = await Supabase.instance.client.functions
          .invoke('geocode', body: {
            'points': [for (final i in missing) points[i]],
          })
          .timeout(const Duration(seconds: 30));

      final data = res.data;
      final raw = data is Map ? data['countries'] as List? : null;

      if (raw == null) {
        debugPrint('Country lookup: unexpected response $data');
        return result;
      }

      for (int n = 0; n < missing.length && n < raw.length; n++) {
        final code = raw[n];
        if (code is! String) continue;

        final i = missing[n];
        result[i] = code;
        _cache[_key(points[i][0], points[i][1])] = code;
      }
    } catch (e) {
      debugPrint('Country lookup failed: $e');
    }

    return result;
  }
}
