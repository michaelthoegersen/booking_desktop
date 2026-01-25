import 'package:flutter/material.dart';

import '../services/distance_service.dart';
import '../models/route_result.dart';

class RoutePlannerPage extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;

  const RoutePlannerPage({
    super.key,
    this.initialFrom,
    this.initialTo,
  });

  @override
  State<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends State<RoutePlannerPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  List<RouteResult> _routes = [];
  RouteResult? _selected;

  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _fromCtrl.text = widget.initialFrom ?? '';
    _toCtrl.text = widget.initialTo ?? '';
  }

  // ------------------------------------------------------------
  // LOAD ROUTES
  // ------------------------------------------------------------
  Future<void> _loadRoutes() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    if (from.isEmpty || to.isEmpty) return;

    setState(() => _loading = true);

    final routes = await DistanceService.getRouteAlternatives(
      from: from,
      to: to,
    );

    setState(() {
      _routes = routes;
      _selected = routes.isNotEmpty ? routes.first : null;
      _loading = false;
    });
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Route planner"),
        actions: [
          if (_selected != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text("Use route"),
            ),
        ],
      ),

      body: Row(
        children: [
          // --------------------------------------------------
          // LEFT PANEL
          // --------------------------------------------------
          SizedBox(
            width: 360,
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

                  FilledButton.icon(
                    icon: const Icon(Icons.alt_route),
                    label: const Text("Find routes"),
                    onPressed: _loading ? null : _loadRoutes,
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _routes.length,
                            itemBuilder: (_, i) {
                              final r = _routes[i];
                              final selected = r == _selected;

                              return Card(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                child: ListTile(
                                  title: Text(r.summary),
                                  subtitle: Text(
                                    '${r.km.toStringAsFixed(1)} km · ${r.durationMin} min',
                                  ),
                                  trailing: selected
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () {
                                    setState(() => _selected = r);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // --------------------------------------------------
          // RIGHT PANEL (PLACEHOLDER FOR MAP)
          // --------------------------------------------------
          Expanded(
            child: Center(
              child: _selected == null
                  ? const Text("No route selected")
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.map, size: 80),
                        const SizedBox(height: 12),
                        Text(
                          _selected!.summary,
                          style: const TextStyle(fontSize: 18),
                        ),
                        Text(
                          '${_selected!.km.toStringAsFixed(1)} km',
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}