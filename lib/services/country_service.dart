import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class CountryService {
  static const String _dartDefineKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  late final String _apiKey = _dartDefineKey.isNotEmpty
      ? _dartDefineKey
      : _loadApiKey();

  static String _loadApiKey() {
    try {
      return dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  final Map<String, String> _cache = {};

  String _key(double lat, double lng) {
    final la = (lat * 50).round() / 50;
    final ln = (lng * 50).round() / 50;
    return "$la,$ln";
  }

  Future<String> getCountry(
    double lat,
    double lng,
  ) async {
    final key = _key(lat, lng);

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // On web: BigDataCloud — free, no API key, proper CORS headers
    if (kIsWeb) {
      return _getCountryWeb(lat, lng, key);
    }

    // Desktop: Google Geocoding API
    if (_apiKey.isEmpty) {
      throw Exception('Missing GOOGLE_MAPS_API_KEY');
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng'
      '&key=$_apiKey',
    );

    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('Geocode failed');
    }

    final data = jsonDecode(res.body);

    for (final r in data['results']) {
      for (final c in r['address_components']) {
        if (c['types'].contains('country')) {
          final country = c['short_name'];
          _cache[key] = country;
          return country;
        }
      }
    }

    _cache[key] = 'Unknown';
    return 'Unknown';
  }

  /// Nominatim reverse geocode (free, CORS OK, 1 req/s)
  static DateTime _lastNominatim = DateTime(2000);

  Future<String> _getCountryWeb(
    double lat,
    double lng,
    String cacheKey,
  ) async {
    try {
      // Rate limit: 1 request per second (Nominatim policy)
      final now = DateTime.now();
      final diff = now.difference(_lastNominatim).inMilliseconds;
      if (diff < 1100) {
        await Future.delayed(Duration(milliseconds: 1100 - diff));
      }
      _lastNominatim = DateTime.now();

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&zoom=3',
      );

      final res = await http.get(url, headers: {
        'Accept': 'application/json',
        'User-Agent': 'TourFlow/1.0 (tourflow-booking)',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        final country =
            (address?['country_code'] as String?)?.toUpperCase() ?? 'Unknown';
        _cache[cacheKey] = country;
        return country;
      }
    } catch (e) {
      debugPrint('Country web lookup failed: $e');
    }

    _cache[cacheKey] = 'Unknown';
    return 'Unknown';
  }
}