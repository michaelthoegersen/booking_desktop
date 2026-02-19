import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/bus_position.dart';
import '../data/city_coords.dart';

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
  // HELPERS
  // ------------------------------------------------------------

  String _normalize(String s) => s.trim().toLowerCase();

  /// Label shown under the bus icon on the map.
  /// Only strips "CSS_" for the three CSS buses; all others get their full name.
  String _busLabel(String bus) {
    const cssBuses = {'CSS_1034', 'CSS_1023', 'CSS_1008'};
    if (cssBuses.contains(bus)) {
      return bus.replaceFirst('CSS_', '');
    }
    return bus;
  }

  // ------------------------------------------------------------
  // BUILD MARKERS  (no clustering — buses side by side when co-located)
  // ------------------------------------------------------------

  List<Marker> _buildMarkers() {
    // 1. Resolve raw position for every bus
    final Map<String, LatLng> rawPos = {};

    widget.busLocations.forEach((bus, position) {
      LatLng? pos;

      if (position.livePos != null) {
        pos = position.livePos;
      }

      if (pos == null && position.place != null) {
        final key = _normalize(position.place!);
        pos = cityCoords[key];
        if (pos == null) {
          debugPrint("❌ City not found: ${position.place} ($key)");
        }
      }

      pos ??= cityCoords[_normalize('Oslo')];

      if (pos == null) {
        debugPrint("🔥 NO POSITION AT ALL FOR $bus");
        return;
      }

      rawPos[bus] = pos;
    });

    // 2. Group buses that share the exact same LatLng
    final Map<String, List<String>> groups = {};
    rawPos.forEach((bus, pos) {
      final key = '${pos.latitude},${pos.longitude}';
      groups.putIfAbsent(key, () => []).add(bus);
    });

    // 3. Spread co-located buses horizontally (≈ 0.10° lng ≈ 6 km apart)
    const double spreadLng = 0.10;
    final Map<String, LatLng> finalPos = {};

    groups.forEach((_, buses) {
      final base = rawPos[buses.first]!;
      for (int i = 0; i < buses.length; i++) {
        final offset = (i - (buses.length - 1) / 2.0) * spreadLng;
        finalPos[buses[i]] = LatLng(base.latitude, base.longitude + offset);
      }
    });

    // 4. Build one Marker per bus
    final List<Marker> markers = [];

    finalPos.forEach((bus, pos) {
      final label = _busLabel(bus);
      final position = widget.busLocations[bus]!;

      markers.add(
        Marker(
          point: pos,
          width: 90,   // wide enough for labels like "YCR 682"
          height: 72,

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
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
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
        padding: EdgeInsets.all(80),
        maxZoom: 6.5,
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

            // No clustering — each bus always gets its own marker
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }
}
