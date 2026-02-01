class LatLngPoint {
  final double lat;
  final double lng;

  LatLngPoint(this.lat, this.lng);
}

class PolylineDecoder {
  // ------------------------------------------------------------
  // Decode Google encoded polyline → List<LatLngPoint>
  // ------------------------------------------------------------
  static List<LatLngPoint> decode(String encoded) {
    final List<LatLngPoint> points = [];

    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;

      int b;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int deltaLat =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      lat += deltaLat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int deltaLng =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      lng += deltaLng;

      points.add(
        LatLngPoint(
          lat / 1e5,
          lng / 1e5,
        ),
      );
    }

    return points;
  }
}