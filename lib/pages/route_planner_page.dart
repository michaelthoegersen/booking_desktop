import 'package:flutter/material.dart';
import '../services/distance_service.dart';
import '../models/route_result.dart';
import 'route_map_view.dart';

class RoutePlannerPage extends StatefulWidget {
  final String initialFrom;
  final String initialTo;

  const RoutePlannerPage({
    super.key,
    required this.initialFrom,
    required this.initialTo,
  });

  @override
  State<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends State<RoutePlannerPage> {
  late TextEditingController fromCtrl;
  late TextEditingController toCtrl;

  List<RouteResult> routes = [];
  RouteResult? selected;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    fromCtrl = TextEditingController(text: widget.initialFrom);
    toCtrl = TextEditingController(text: widget.initialTo);
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    routes = await DistanceService.getRouteAlternatives(
      from: fromCtrl.text,
      to: toCtrl.text,
    );
    selected = routes.first;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Route planner"),
        actions: [
          if (selected != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text("Use route"),
            )
        ],
      ),
      body: Row(
  children: [
    // LEFT PANEL
    SizedBox(
      width: 380,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(labelText: "From"),
              onSubmitted: (_) => _loadRoutes(),
            ),

            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(labelText: "To"),
              onSubmitted: (_) => _loadRoutes(),
            ),

            const SizedBox(height: 12),

            FilledButton(
              onPressed: _loadRoutes,
              child: const Text("Finn ruter"),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: _routes.length,
                itemBuilder: (_, i) {
                  final r = _routes[i];

                  return ListTile(
                    title: Text(r.summary),
                    subtitle: Text(
                      "${r.km.toStringAsFixed(1)} km · ${r.durationMin} min",
                    ),
                    selected: r == _selected,
                    onTap: () {
                      setState(() => _selected = r);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),

    // RIGHT PANEL – MAP
    Expanded(
      child: _selected == null
          ? const Center(child: Text("Velg en rute"))
          : RouteMapView(
              from: _selected!.from,
              to: _selected!.to,
            ),
    ),
  ],
),