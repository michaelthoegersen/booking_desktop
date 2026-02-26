import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/google_routes_service.dart';
import '../services/route_country_analyzer.dart';
import '../services/polyline_decoder.dart';
import '../services/routes_service.dart';

class RouteCalcResult {
  final String from;
  final String to;
  final List<String> via;
  final double km;
  final Map<String, double> countryKm;

  RouteCalcResult({
    required this.from,
    required this.to,
    required this.via,
    required this.km,
    required this.countryKm,
  });
}

class RoutePopupDialog extends StatefulWidget {
  final String start;
  final List<String> stops;

  const RoutePopupDialog({
    super.key,
    required this.start,
    required this.stops,
  });

  @override
  State<RoutePopupDialog> createState() =>
      _RoutePopupDialogState();
}

class _RoutePopupDialogState extends State<RoutePopupDialog> {
  final GoogleRoutesService _google = GoogleRoutesService();
  final RouteCountryAnalyzer _analyzer = RouteCountryAnalyzer();
  final RoutesService _routes = RoutesService();

  bool _loading = true;
  String? _error;

  // ================= MULTI ROUTES =================
  List<List<LatLng>> _allRoutes = [];

  // ✅ NYTT: per route data
  List<double> _routeKm = [];
  List<Map<String, double>> _routeCountryKm = [];

  int _activeRouteIndex = 0;

  double? _distanceKm;
  Map<String, double> _countryKm = {};

  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  final TextEditingController _kmCtrl = TextEditingController();

  final List<TextEditingController> _viaCtrls = [];

  bool _hasFerry = false;
  bool _hasBridge = false;

  final TextEditingController _ferryNameCtrl =
      TextEditingController();

  // =================================================
  // RESOLVE PLACE
  // =================================================
  String _resolveValidPlace(List<String> places, int index) {
    String lastValid = '';

    for (int i = 0; i <= index && i < places.length; i++) {
      final p = places[i].trim();

      if (p.isNotEmpty &&
          p.toLowerCase() != 'travel' &&
          p.toLowerCase() != 'off') {
        lastValid = p;
      }
    }

    return lastValid;
  }

  // =================================================
  // INIT
  // =================================================
  @override
  void initState() {
    super.initState();

    final allPlaces = [
      widget.start,
      ...widget.stops,
    ];

    final from = _resolveValidPlace(allPlaces, 0);

    final to = allPlaces.isNotEmpty
        ? _resolveValidPlace(
            allPlaces,
            allPlaces.length - 1,
          )
        : '';

    _fromCtrl = TextEditingController(text: from);
    _toCtrl = TextEditingController(text: to);

    _loadRoute();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _kmCtrl.dispose();
    _ferryNameCtrl.dispose();

    for (final c in _viaCtrls) {
      c.dispose();
    }

    super.dispose();
  }
// =================================================
// BUILD EXTRA
// =================================================
String _buildExtra() {
  final parts = <String>[];

  if (_hasFerry) parts.add("Ferry");
  if (_hasBridge) parts.add("Bridge");

  return parts.join("/");
}
  // =================================================
  // BUILD PLACES
  // =================================================
  List<String> _buildAllPlaces() {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    if (from.isEmpty || to.isEmpty) return [];

    final vias = _viaCtrls
        .map((c) => c.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return [from, ...vias, to];
  }

  // =================================================
  // LOAD ROUTES
  // =================================================
  Future<void> _loadRoute() async {
  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    final places = _buildAllPlaces();

    // ❗ Ikke kast – bare gi tom popup
    if (places.length < 2) {
      setState(() {
        _allRoutes = [];
        _routeKm = [];
        _routeCountryKm = [];
        _distanceKm = null;
        _countryKm = {};
        _loading = false;
      });
      return;
    }

    final res = await _google.getRouteWithVia(
      places: places,
    );

    final routes =
        List<Map<String, dynamic>>.from(res['routes'] ?? []);

    final List<List<LatLng>> lines = [];
    final List<double> kms = [];
    final List<Map<String, double>> countries = [];

    for (final r in routes) {
      final rawPoints = r['rawPoints'] as List?;
      final polyline = r['polyline'] as String?;
      final meters = r['distanceMeters'] as num?;

      if (meters == null) continue;

      List<LatLng> line;

      if (rawPoints != null && rawPoints.isNotEmpty) {
        // Web: raw [lat, lon] list from OSRM (no polyline encoding)
        line = rawPoints.map<LatLng>((p) {
          final pair = p as List;
          return LatLng(
            (pair[0] as num).toDouble(),
            (pair[1] as num).toDouble(),
          );
        }).toList();
      } else if (polyline != null && polyline.isNotEmpty) {
        // Desktop: encoded polyline from Google Routes API
        final decoded = PolylineDecoder.decode(polyline);
        if (decoded.isEmpty) continue;
        line = decoded.map((p) => LatLng(p.lat, p.lng)).toList();
      } else {
        continue;
      }

      if (line.isEmpty) continue;

      lines.add(line);

      final km = meters / 1000;

      Map<String, double> country = {};
      try {
        if (rawPoints != null && rawPoints.isNotEmpty) {
          final pts = rawPoints.map<List<double>>((p) {
            final pair = p as List;
            return [
              (pair[0] as num).toDouble(),
              (pair[1] as num).toDouble(),
            ];
          }).toList();
          country = await _analyzer.kmPerCountryFromPoints(pts);
        } else if (polyline != null && polyline.isNotEmpty) {
          country = await _analyzer.kmPerCountry(polyline);
        }
      } catch (e) {
        debugPrint('Country analysis failed (non-fatal): $e');
      }

      kms.add(km);
      countries.add(country);
    }

    // ❗ Ingen ruter? Helt OK.
    if (lines.isEmpty) {
      setState(() {
        _allRoutes = [];
        _routeKm = [];
        _routeCountryKm = [];
        _distanceKm = null;
        _countryKm = {};
        _loading = false;
      });
      return;
    }

    setState(() {
      _allRoutes = lines;
      _routeKm = kms;
      _routeCountryKm = countries;
      _activeRouteIndex = 0;
      _distanceKm = kms.first;
      _countryKm = countries.first;
      _loading = false;
    });
    _kmCtrl.text = kms.first.toStringAsFixed(0);

  } catch (e) {
    // ❗ ALDRI blokker popup
    debugPrint("Route load failed: $e");

    setState(() {
      _allRoutes = [];
      _routeKm = [];
      _routeCountryKm = [];
      _distanceKm = null;
      _countryKm = {};
      _loading = false;
    });
  }
}

  // =================================================
// SAVE
// =================================================
Future<void> _save() async {
  final kmText = _kmCtrl.text.trim().replaceAll(',', '.');
  final km = double.tryParse(kmText) ?? _distanceKm;

  if (km == null || km <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Enter km before saving")),
    );
    return;
  }

  try {
    final extra = _buildExtra();
    final ferryName = _ferryNameCtrl.text.trim();
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    // ----------------------------------------
    // ALLOWED COUNTRIES ONLY
    // ----------------------------------------

    const allowed = {
      'dk',
      'be',
      'pl',
      'at',
      'hr',
      'si',
      'de',
      'se',
    };

    final Map<String, double> countryFields = {};

    _countryKm.forEach((country, km) {
      final code = country.toLowerCase();

      if (allowed.contains(code)) {
        countryFields['km_$code'] = km;
      }
    });

    debugPrint("🌍 Country KM (filtered): $countryFields");

    // ----------------------------------------
    // BUILD DATA
    // ----------------------------------------

    final data = {
      'from_place': from,
      'to_place': to,

      // metadata
      'extra': extra,
      'ferry_name': ferryName,

      // total
      'distance_total_km': km,

      // per country (only allowed)
      ...countryFields,
    };

    debugPrint("💾 Saving route: $data");

    // ----------------------------------------
    // SAVE
    // ----------------------------------------

    await Supabase.instance.client
        .from('routes_all')
        .upsert(
          data,
          onConflict: 'from_place,to_place',
        );

    debugPrint("✅ Route saved");

    Navigator.pop(context, true);

  } catch (e, st) {
    debugPrint("❌ Save failed: $e");
    debugPrint("$st");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Save failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
  // =================================================
  // UI
  // =================================================
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [

          const Expanded(
            child: Text(
              "Route preview",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          if (_distanceKm != null)
            Text("${_distanceKm!.toStringAsFixed(0)} km"),

          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return Row(
      children: [

        SizedBox(
          width: 340,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildEditor(),
          ),
        ),

        const VerticalDivider(),

        Expanded(child: _buildMap()),
      ],
    );
  }

  // =================================================
  // EDITOR
  // =================================================
  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          TextField(
            controller: _fromCtrl,
            decoration:
                const InputDecoration(labelText: "From"),
          ),

          TextField(
            controller: _toCtrl,
            decoration:
                const InputDecoration(labelText: "To"),
          ),

          TextField(
            controller: _kmCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "KM"),
          ),

          const SizedBox(height: 12),

          ..._viaCtrls.map(_buildViaRow),

          TextButton.icon(
            onPressed: () {
              setState(() {
                _viaCtrls.add(TextEditingController());
              });
            },
            icon: const Icon(Icons.add),
            label: const Text("Add via"),
          ),

          const Divider(),

          if (_allRoutes.length > 1) ...[

            const Text(
              "Alternative routes",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            for (int i = 0; i < _allRoutes.length; i++)
  RadioListTile<int>(
    dense: true,
    value: i,
    groupValue: _activeRouteIndex,

    title: Text(
      "Route ${i + 1} (${_routeKm.isNotEmpty ? _routeKm[i].toStringAsFixed(0) : "?"} km)",
    ),
                onChanged: (v) {
                  if (v == null) return;

                  setState(() {
                    _activeRouteIndex = v;

                    // ✅ AUTO UPDATE
                    _distanceKm = _routeKm[v];
                    _countryKm = _routeCountryKm[v];
                  });
                },
              ),

            const Divider(),
          ],

          _buildCountryKm(),

const Divider(),

// EXTRAS
CheckboxListTile(
  title: const Text("Ferry"),
  value: _hasFerry,
  onChanged: (v) {
    setState(() => _hasFerry = v ?? false);
  },
),

CheckboxListTile(
  title: const Text("Bridge"),
  value: _hasBridge,
  onChanged: (v) {
    setState(() => _hasBridge = v ?? false);
  },
),

TextField(
  controller: _ferryNameCtrl,
  decoration: const InputDecoration(
    labelText: "Ferry / Bridge name",
    prefixIcon: Icon(Icons.directions_boat),
  ),
),

const SizedBox(height: 24),

          FilledButton(
            onPressed: _loadRoute,
            child: const Text("Recalc"),
          ),

          const SizedBox(height: 8),

          FilledButton(
            onPressed: _save,
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // =================================================
  // VIA ROW
  // =================================================
  Widget _buildViaRow(TextEditingController c) {
    return Row(
      children: [

        Expanded(
          child: TextField(
            controller: c,
            decoration:
                const InputDecoration(labelText: "Via"),
          ),
        ),

        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _viaCtrls.remove(c);
              c.dispose();
            });
          },
        ),
      ],
    );
  }

  // =================================================
  // COUNTRY KM
  // =================================================
  Widget _buildCountryKm() {
    if (_countryKm.isEmpty) return const SizedBox();

    final list = _countryKm.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "Distance per country",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 6),

        ...list.map(
          (e) => Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [

              Text(e.key),

              Text(
                "${e.value.toStringAsFixed(1)} km",
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
      ],
    );
  }

  // =================================================
  // MAP
  // =================================================
  Widget _buildMap() {
    if (_allRoutes.isEmpty) {
      return const Center(
        child: Text("Route cached (no map)"),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter:
            _allRoutes[_activeRouteIndex].first,
        initialZoom: 6,
      ),

      children: [

        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: true,
          maxZoom: 19,
          userAgentPackageName: 'com.tourflow.app',
          errorTileCallback: (tile, error, stackTrace) {},
        ),

        PolylineLayer(
          polylines: [

            for (int i = 0; i < _allRoutes.length; i++)
              if (i != _activeRouteIndex)
                Polyline(
                  points: _allRoutes[i],
                  strokeWidth: 3,
                  color: Colors.grey.withOpacity(0.5),
                ),

            Polyline(
              points: _allRoutes[_activeRouteIndex],
              strokeWidth: 5,
              color: Colors.blue,
            ),
          ],
        ),
      ],
    );
  }
}