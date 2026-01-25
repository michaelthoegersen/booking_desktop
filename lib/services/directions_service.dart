import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class DirectionsService {
  static final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  static Future<List<_RouteOption>> getRoutes({
    required String from,
    required String to,
  }) async {
    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${Uri.encodeComponent(from)}'
        '&destination=${Uri.encodeComponent(to)}'
        '&alternatives=true'
        '&units=metric'
        '&key=$_apiKey';

    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);

    if (data['status'] != 'OK') {
      throw Exception(data['error_message'] ?? 'Directions error');
    }

    final List<_RouteOption> routes = [];

    for (final r in data['routes']) {
      final leg = r['legs'][0];
      final meters = leg['distance']['value'];
      final km = meters / 1000.0;

      final polylinePoints =
          PolylinePoints().decodePolyline(r['overview_polyline']['points']);

      routes.add(
        _RouteOption(
          km: km,
          summary: r['summary'] ?? 'Route',
          polyline: polylinePoints
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
        ),
      );
    }

    return routes;
  }
}

class _RouteOption {
  final double km;
  final String summary;
  final List<LatLng> polyline;

  _RouteOption({
    required this.km,
    required this.summary,
    required this.polyline,
  });
}