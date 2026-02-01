import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/lat_lng.dart';

class ReverseGeocodeService {
  final _key =
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  Future<String> getCountry(LatLng p) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=${p.lat},${p.lng}'
      '&key=$_key',
    );

    final res = await http.get(url);

    if (res.statusCode != 200) {
      return 'Unknown';
    }

    final data = jsonDecode(res.body);

    final results = data['results'] as List;

    if (results.isEmpty) return 'Unknown';

    final comps =
        results[0]['address_components'] as List;

    for (final c in comps) {
      final types = c['types'] as List;

      if (types.contains('country')) {
        return c['long_name'];
      }
    }

    return 'Unknown';
  }
}