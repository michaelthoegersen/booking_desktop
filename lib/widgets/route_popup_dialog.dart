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

  List<LatLng> _routeLine = [];

  double? _distanceKm;
  Map<String, double> _countryKm = {};

  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;

  final List<TextEditingController> _viaCtrls = [];

  // ================= NEW FIELDS =================

  bool _hasFerry = false;
  bool _hasBridge = false;

  final TextEditingController _ferryNameCtrl =
      TextEditingController();

  final TextEditingController _tollCtrl =
      TextEditingController();

  // =================================================
  // RESOLVE LAST VALID PLACE (SKIP Travel / Off)
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

    // Build full list
    final allPlaces = [
      widget.start,
      ...widget.stops,
    ];

    // Resolve valid FROM / TO
    final from = _resolveValidPlace(allPlaces, 0);

    final to = allPlaces.isNotEmpty
        ? _resolveValidPlace(
            allPlaces,
            allPlaces.length - 1,
          )
        : '';

    _fromCtrl = TextEditingController(text: from);
    _toCtrl = TextEditingController(text: to);

    _viaCtrls.clear();

    // Reset extras
    _hasFerry = false;
    _hasBridge = false;
    _ferryNameCtrl.clear();
    _tollCtrl.clear();

    _loadRoute();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _ferryNameCtrl.dispose();
    _tollCtrl.dispose();

    for (final c in _viaCtrls) {
      c.dispose();
    }

    super.dispose();
  }

  // =================================================
  // BUILD EXTRA FIELD
  // =================================================
  String _buildExtra() {
    final parts = <String>[];

    if (_hasFerry) parts.add("Ferry");
    if (_hasBridge) parts.add("Bridge");

    return parts.join("/");
  }

  // =================================================
  // BUILD ALL PLACES
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
  // FIND FIRST MISSING SEGMENT
  // =================================================
  Future<List<String>?> _findFirstMissingSegment() async {
    final all = _buildAllPlaces();

    if (all.length < 2) return null;

    for (int i = 0; i < all.length - 1; i++) {
      final a = all[i];
      final b = all[i + 1];

      final cached =
          await _routes.findRoute(from: a, to: b);

      if (cached == null) {
        return [a, b];
      }
    }

    return null;
  }

  // =================================================
  // LOAD ROUTE
  // =================================================
  Future<void> _loadRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      while (true) {
        final segment =
            await _findFirstMissingSegment();

        if (segment == null) break;

        final from = segment[0];
        final to = segment[1];

        final res = await _google.getRouteWithVia(
          places: [from, to],
        );

        final meters = res['distanceMeters'] as num;
        final polyline = res['polyline'] as String;

        final km = meters / 1000;

        final countryKm =
            await _analyzer.kmPerCountry(polyline);

        final decoded =
            PolylineDecoder.decode(polyline);

        final line = decoded
            .map((p) => LatLng(p.lat, p.lng))
            .toList();

        if (line.isEmpty) {
          throw Exception("Empty route");
        }

        await _routes.findOrCreateRoute(
          from: from,
          to: to,
          totalKm: km,
          countryKm: countryKm,
        );

        setState(() {
          _routeLine = line;
          _distanceKm = km;
          _countryKm = countryKm;
        });
      }

      setState(() => _loading = false);

    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // =================================================
  // SAVE
  // =================================================
  Future<void> _save() async {
    if (_distanceKm == null) return;

    final extra = _buildExtra();
    final ferryName = _ferryNameCtrl.text.trim();

    final toll = double.tryParse(
      _tollCtrl.text.replaceAll(',', '.'),
    ) ?? 0.0;

    await Supabase.instance.client
        .from('routes_all')
        .update({
          'extra': extra,
          'ferry_name': ferryName,
          'toll_nightliner': toll,
        })
        .eq('from_place', _fromCtrl.text.trim())
        .eq('to_place', _toCtrl.text.trim());

    Navigator.pop(
      context,
      RouteCalcResult(
        from: _fromCtrl.text.trim(),
        to: _toCtrl.text.trim(),
        via: _viaCtrls
            .map((c) => c.text.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        km: _distanceKm!,
        countryKm: _countryKm,
      ),
    );
  }

  // =================================================
  // UI
  // =================================================
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        height: 600,
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
        SizedBox(width: 300, child: _buildEditor()),
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

          const SizedBox(height: 12),

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

          TextField(
            controller: _tollCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Toll (Nightliner)",
              prefixIcon: Icon(Icons.toll),
            ),
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

          const Spacer(),

          FilledButton(
            onPressed: _loadRoute,
            child: const Text("Recalc"),
          ),

          FilledButton(
            onPressed: _save,
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildViaRow(TextEditingController c) {
    return Row(
      children: [
        Expanded(child: TextField(controller: c)),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _viaCtrls.remove(c);
            });
          },
        ),
      ],
    );
  }

  // =================================================
  // MAP
  // =================================================
  Widget _buildMap() {
    if (_routeLine.isEmpty) {
      return const Center(
        child: Text("Route cached (no map)"),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: _routeLine.first,
        initialZoom: 6,
      ),
      children: [
        TileLayer(
          urlTemplate:
              "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        ),

        PolylineLayer(
          polylines: [
            Polyline(
              points: _routeLine,
              strokeWidth: 4,
              color: Colors.blue,
            ),
          ],
        ),
      ],
    );
  }
}