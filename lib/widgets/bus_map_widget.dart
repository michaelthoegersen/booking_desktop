import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../pages/dashboard_page.dart';
import '../models/bus_position.dart';
import '../data/city_coords.dart'; // eller riktig sti

class BusMapWidget extends StatefulWidget {
  final Map<String, BusPosition> busLocations;
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
  final MapController _mapController = MapController();

  // ------------------------------------------------------------
  // NORMALIZE STRING
  // ------------------------------------------------------------

  String _normalize(String s) {
    return s.trim().toLowerCase();
  }
  // ------------------------------------------------------------
  // BUILD MARKERS
  // ------------------------------------------------------------

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];

    widget.busLocations.forEach((bus, position) {

  LatLng? pos;

  // 1️⃣ Live-posisjon først
  if (position.livePos != null) {
    pos = position.livePos;
  }

  // 2️⃣ Ellers bruk by
  if (pos == null && position.place != null) {

    final key = _normalize(position.place!);

    pos = cityCoords[key];

    if (pos == null) {
      debugPrint("❌ City not found: ${position.place} ($key)");
    }
  }

  // 3️⃣ Hard fallback
  pos ??= cityCoords[_normalize('Oslo')];

  if (pos == null) {
    debugPrint("🔥 NO POSITION AT ALL FOR $bus");
    return;
  }

  markers.add(
    Marker(
      point: pos,
      width: 60,
      height: 70,

      child: Tooltip(
        message: '$bus\n${position.place ?? "On route"}',

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Image.asset(
              'assets/pdf/buses/DDBuskart.png',
              width: 42,
              height: 42,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 3),

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
  );
});

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
      padding: EdgeInsets.all(80), // 👈 mer luft
      maxZoom: 6.5,                // 👈 aldri for tett
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

            TileLayer(
              urlTemplate:
                  'https://api.maptiler.com/maps/streets/256/{z}/{x}/{y}.png?key=qLneWyVuo1A6hcUjh3iS',

              userAgentPackageName: 'com.tourflow.app',
            ),

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