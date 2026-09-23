import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_env.dart';

class CountryService {
  String get _apiKey => AppEnv.googleMapsApiKey;

  Future<String> getCountry(
    double lat,
    double lng,
  ) async {
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json"
      "?latlng=$lat,$lng"
      "&key=$_apiKey",
    );

    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception("Geocode error");
    }

    final data = jsonDecode(res.body);

    final results = data['results'];

    for (final r in results) {
      for (final c in r['address_components']) {
        if (c['types'].contains('country')) {
          return c['long_name'];
        }
      }
    }

    return "Unknown";
  }
}