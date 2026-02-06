import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapTilerRoutingService {
  static const String _apiKey = 'qLneWyVuo1A6hcUjh3iS';

  static Future<List<LatLng>> getRoute(
    LatLng from,
    LatLng to,
  ) async {
    final url =
        'https://api.maptiler.com/directions/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?snap=true&geometries=geojson&key=$_apiKey';

    final uri = Uri.parse(url);

    print("🗺️ ROUTE URL: $uri");

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
        'Routing failed: ${res.statusCode} ${res.body}',
      );
    }

    final data = jsonDecode(res.body);

    final routes = data['routes'];

    if (routes == null || routes.isEmpty) {
      throw Exception('No routes found');
    }

    final coords =
        routes[0]['geometry']['coordinates'] as List;

    return coords
        .map<LatLng>((c) => LatLng(c[1], c[0]))
        .toList();
  }
}