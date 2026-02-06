import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OpenRouteService {
  // 👉 DIN KEY
  static const String _apiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImU1Nzg0NDljYzIyMjQ2NjdiZjA3YzI5YjE5YmUyMWQwIiwiaCI6Im11cm11cjY0In0=";

  static const String _url =
      "https://api.openrouteservice.org/v2/directions/driving-car/geojson";

  static Future<List<LatLng>> getRoute(
    LatLng from,
    LatLng to,
  ) async {
    final uri = Uri.parse(_url);

    final body = jsonEncode({
      "coordinates": [
        [from.longitude, from.latitude],
        [to.longitude, to.latitude],
      ]
    });

    final res = await http.post(
      uri,
      headers: {
        "Authorization": _apiKey,
        "Content-Type": "application/json",
      },
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception(
        "OpenRoute error ${res.statusCode}: ${res.body}",
      );
    }

    final data = jsonDecode(res.body);

    // ✅ Sikker parsing
    if (data == null ||
        data["features"] == null ||
        data["features"].isEmpty) {
      throw Exception("Invalid route response: $data");
    }

    final geometry = data["features"][0]["geometry"];

    if (geometry == null ||
        geometry["coordinates"] == null) {
      throw Exception("Missing geometry: $data");
    }

    final coords = geometry["coordinates"] as List;

    return coords.map<LatLng>((c) {
      return LatLng(c[1], c[0]);
    }).toList();
  }
}