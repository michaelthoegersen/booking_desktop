import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/directions_service.dart';
import '../models/route_result.dart';

class RouteEditorPage extends StatefulWidget {
  final String from;
  final String to;

  const RouteEditorPage({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  State<RouteEditorPage> createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage> {
  GoogleMapController? _map;
  bool _loading = true;

  List<dynamic> _routes = [];
  int _selectedIndex = 0;

  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final res = await DirectionsService.getRoutes(
      from: widget.from,
      to: widget.to,
    );

    setState(() {
      _routes = res;
      _selectedIndex = 0;
      _draw();
      _loading = false;
    });
  }

  void _draw() {
    _polylines.clear();

    for (int i = 0; i < _routes.length; i++) {
      final r = _routes[i];
      _polylines.add(
        Polyline(
          polylineId: PolylineId('r$i'),
          points: r.polyline,
          color: i == _selectedIndex ? Colors.blue : Colors.grey,
          width: i == _selectedIndex ? 6 : 4,
        ),
      );
    }

    if (_routes.isNotEmpty && _map != null) {
      _map!.animateCamera(
        CameraUpdate.newLatLngBounds(
          _boundsFromPolyline(_routes[_selectedIndex].polyline),
          80,
        ),
      );
    }
  }

  LatLngBounds _boundsFromPolyline(List<LatLng> pts) {
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.from} → ${widget.to}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    onMapCreated: (c) => _map = c,
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(52.52, 13.405),
                      zoom: 5,
                    ),
                    polylines: _polylines,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  height: 180,
                  child: ListView.builder(
                    itemCount: _routes.length,
                    itemBuilder: (_, i) {
                      final r = _routes[i];
                      return ListTile(
                        title: Text(
                          '${r.summary} – ${r.km.toStringAsFixed(1)} km',
                        ),
                        leading: Radio<int>(
                          value: i,
                          groupValue: _selectedIndex,
                          onChanged: (v) {
                            setState(() {
                              _selectedIndex = v!;
                              _draw();
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () {
                      final r = _routes[_selectedIndex];
                      Navigator.pop(
                        context,
                        RouteResult(
                          km: r.km,
                          summary: r.summary,
                          polyline: r.polyline,
                        ),
                      );
                    },
                    child: const Text('Use this route'),
                  ),
                ),
              ],
            ),
    );
  }
}