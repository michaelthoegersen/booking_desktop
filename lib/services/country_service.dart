import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class CountryService {
  static const String _dartDefineKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  final String _apiKey = _dartDefineKey.isNotEmpty
      ? _dartDefineKey
      : (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '');

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

  Future<String> _getCountryWeb(
    double lat,
    double lng,
    String cacheKey,
  ) async {
    try {
      final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=$lat&longitude=$lng&localityLanguage=en',
      );

      final res = await http
          .get(url)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final country =
            (data['countryCode'] as String?)?.toUpperCase() ?? 'Unknown';
        _cache[cacheKey] = country;
        return country;
      }
    } catch (_) {}

    _cache[cacheKey] = 'Unknown';
    return 'Unknown';
  }
}