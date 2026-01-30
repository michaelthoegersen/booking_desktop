import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

class BusMapWidget extends StatefulWidget {
  final Map<String, String> busLocations;
  final VoidCallback onRefresh;

  const BusMapWidget({
    super.key,
    required this.busLocations,
    required this.onRefresh,
  });

  @override
  State<BusMapWidget> createState() => _BusMapWidgetState();
}

class _BusMapWidgetState extends State<BusMapWidget> {
    String _busLabel(String bus) {
  // CSS_1034 -> 1034
  if (bus.contains('_')) {
    return bus.split('_').last;
  }

  return bus; // fallback
}
  final MapController _mapController = MapController();

  // ------------------------------------------------------------
// CITY → COORDINATES (EUROPE MAJOR CITIES)
// ------------------------------------------------------------

final Map<String, LatLng> _cityCoords = {

  // ---------------- NORDICS ----------------
  'Linköping': LatLng(58.4108, 15.6214),
  'Stockholm': LatLng(59.3293, 18.0686),
  'Göteborg': LatLng(57.7089, 11.9746),
  'Malmö': LatLng(55.6050, 13.0038),
  'Uppsala': LatLng(59.8586, 17.6389),
  'Helsinki': LatLng(60.1699, 24.9384),
  'Tampere': LatLng(61.4978, 23.7610),
  'Turku': LatLng(60.4518, 22.2666),
  'Oslo': LatLng(59.9139, 10.7522),
  'Bergen': LatLng(60.3913, 5.3221),
  'Trondheim': LatLng(63.4305, 10.3951),
  'Copenhagen': LatLng(55.6761, 12.5683),
  'Aarhus': LatLng(56.1629, 10.2039),
  'Reykjavik': LatLng(64.1466, -21.9426),

  // ---------------- UK / IRELAND ----------------
  'London': LatLng(51.5074, -0.1278),
  'Manchester': LatLng(53.4808, -2.2426),
  'Birmingham': LatLng(52.4862, -1.8904),
  'Liverpool': LatLng(53.4084, -2.9916),
  'Leeds': LatLng(53.8008, -1.5491),
  'Edinburgh': LatLng(55.9533, -3.1883),
  'Glasgow': LatLng(55.8642, -4.2518),
  'Dublin': LatLng(53.3498, -6.2603),
  'Belfast': LatLng(54.5973, -5.9301),

  // ---------------- FRANCE / BENELUX ----------------
  'Paris': LatLng(48.8566, 2.3522),
  'Lyon': LatLng(45.7640, 4.8357),
  'Marseille': LatLng(43.2965, 5.3698),
  'Nice': LatLng(43.7102, 7.2620),
  'Lille': LatLng(50.6292, 3.0573),
  'Brussels': LatLng(50.8503, 4.3517),
  'Antwerp': LatLng(51.2194, 4.4025),
  'Amsterdam': LatLng(52.3676, 4.9041),
  'Rotterdam': LatLng(51.9244, 4.4777),
  'The Hague': LatLng(52.0705, 4.3007),
  'Luxembourg': LatLng(49.6116, 6.1319),

  // ---------------- GERMANY / AUSTRIA / SWISS ----------------
  'Berlin': LatLng(52.5200, 13.4050),
  'Hamburg': LatLng(53.5511, 9.9937),
  'Munich': LatLng(48.1351, 11.5820),
  'Cologne': LatLng(50.9375, 6.9603),
  'Frankfurt': LatLng(50.1109, 8.6821),
  'Stuttgart': LatLng(48.7758, 9.1829),
  'Düsseldorf': LatLng(51.2277, 6.7735),
  'Leipzig': LatLng(51.3397, 12.3731),
  'Vienna': LatLng(48.2082, 16.3738),
  'Salzburg': LatLng(47.8095, 13.0550),
  'Zurich': LatLng(47.3769, 8.5417),
  'Geneva': LatLng(46.2044, 6.1432),
  'Basel': LatLng(47.5596, 7.5886),

  // ---------------- SPAIN / PORTUGAL ----------------
  'Madrid': LatLng(40.4168, -3.7038),
  'Barcelona': LatLng(41.3851, 2.1734),
  'Valencia': LatLng(39.4699, -0.3763),
  'Seville': LatLng(37.3891, -5.9845),
  'Bilbao': LatLng(43.2630, -2.9350),
  'Lisbon': LatLng(38.7223, -9.1393),
  'Porto': LatLng(41.1579, -8.6291),

  // ---------------- ITALY ----------------
  'Rome': LatLng(41.9028, 12.4964),
  'Milan': LatLng(45.4642, 9.1900),
  'Naples': LatLng(40.8518, 14.2681),
  'Turin': LatLng(45.0703, 7.6869),
  'Florence': LatLng(43.7696, 11.2558),
  'Venice': LatLng(45.4408, 12.3155),
  'Bologna': LatLng(44.4949, 11.3426),

  // ---------------- EASTERN EUROPE ----------------
  'Warsaw': LatLng(52.2297, 21.0122),
  'Krakow': LatLng(50.0647, 19.9450),
  'Gdansk': LatLng(54.3520, 18.6466),
  'Prague': LatLng(50.0755, 14.4378),
  'Brno': LatLng(49.1951, 16.6068),
  'Bratislava': LatLng(48.1486, 17.1077),
  'Budapest': LatLng(47.4979, 19.0402),
  'Vienna': LatLng(48.2082, 16.3738),
  'Bucharest': LatLng(44.4268, 26.1025),
  'Sofia': LatLng(42.6977, 23.3219),
  'Belgrade': LatLng(44.7866, 20.4489),
  'Zagreb': LatLng(45.8150, 15.9819),
  'Ljubljana': LatLng(46.0569, 14.5058),

  // ---------------- BALTICS ----------------
  'Tallinn': LatLng(59.4370, 24.7536),
  'Riga': LatLng(56.9496, 24.1052),
  'Vilnius': LatLng(54.6872, 25.2797),

  // ---------------- GREECE / TURKEY ----------------
  'Athens': LatLng(37.9838, 23.7275),
  'Thessaloniki': LatLng(40.6401, 22.9444),
  'Istanbul': LatLng(41.0082, 28.9784),
  'Ankara': LatLng(39.9334, 32.8597),

};

  // ------------------------------------------------------------
  // BUILD MARKERS
  // ------------------------------------------------------------

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];

    widget.busLocations.forEach((bus, place) {
      final LatLng pos =
          _cityCoords[place] ?? _cityCoords['Linköping']!;

      markers.add(
  Marker(
    point: pos,

    // 👇 Viktig: større område → ingen overflow
    width: 60,
    height: 70,

    child: Tooltip(
      message: '$bus\n$place',

      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [

          // ================= BUSS-BILDE =================
          Image.asset(
            'assets/pdf/buses/DDBuskart.png',
            width: 42,   // 👈 større ikon
            height: 42,
            fit: BoxFit.contain,
          ),

          const SizedBox(height: 3),

          // ================= LABEL =================
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 2,
            ),

            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(7),
            ),

            child: Text(
              bus.replaceAll(RegExp(r'[^0-9]'), ''),

              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);    });

    return markers;
  }

  // ------------------------------------------------------------
  // AUTO ZOOM
  // ------------------------------------------------------------

  void _autoZoom(List<Marker> markers) {
    if (markers.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(
      markers.map((m) => m.point).toList(),
    );

    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(
        padding: EdgeInsets.all(40),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoZoom(markers);
    });

    return Container(
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),

      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),

        child: FlutterMap(
          mapController: _mapController,

          options: const MapOptions(
            initialCenter: LatLng(58.4108, 15.6214),
            initialZoom: 6,
          ),

          children: [

            // ---------------- TILE (MapTiler)
            TileLayer(
              urlTemplate:
                  'https://api.maptiler.com/maps/streets/256/{z}/{x}/{y}.png?key=qLneWyVuo1A6hcUjh3iS',

              userAgentPackageName: 'com.tourflow.app',

              errorTileCallback: (tile, error, stackTrace) {
                debugPrint('Tile error: $error');
              },
            ),

            // ---------------- CLUSTER
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 45,
                size: const Size(40, 40),

                markers: markers,

                builder: (context, cluster) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),

                    child: Center(
                      child: Text(
                        cluster.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}