import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/route_result.dart';

class DistanceService {
  static Future<List<RouteResult>> getRouteAlternatives({
    required String from,
    required String to,
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    final origin = Uri.encodeComponent(from);
    final destination = Uri.encodeComponent(to);

    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin'
        '&destination=$destination'
        '&alternatives=true'
        '&key=$apiKey';

    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);

    if (data['status'] != 'OK') {
      throw Exception(data['error_message'] ?? 'Directions error');
    }

    return (data['routes'] as List).map((r) {
      final leg = r['legs'][0];
      return RouteResult(
        summary: r['summary'] ?? 'Uten navn',
        km: leg['distance']['value'] / 1000,
        durationMin: (leg['duration']['value'] / 60).round(),
        polylineEncoded: r['overview_polyline']['points'],
      );
    }).toList();
  }
}