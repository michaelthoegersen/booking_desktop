import 'package:flutter/material.dart';

import '../models/route_result.dart';
import '../services/routes_service.dart';
import 'route_edit_dialog.dart';

class RoutesAdminPage extends StatefulWidget {
  const RoutesAdminPage({super.key});

  @override
  State<RoutesAdminPage> createState() => _RoutesAdminPageState();
}

class _RoutesAdminPageState extends State<RoutesAdminPage> {
  final _service = RoutesService();

  List<RouteResult> _routes = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final res = await _service.getAllRoutes();

      _routes = res
          .map((e) => RouteResult.fromMap(e))
          .toList();
    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() => _loading = false);
  }

  Future<void> _openEditor([RouteResult? route]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => RouteEditDialog(route: route),
    );

    if (changed == true) {
      await _load();
    }
  }

  Future<void> _delete(RouteResult route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete route'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _service.deleteRoute(route.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes admin'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? const Center(child: Text('No routes found'))
              : ListView.separated(
                  itemCount: _routes.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final r = _routes[i];

                    return ListTile(
                      title: Text('${r.from} → ${r.to}'),
                      subtitle: Text('${r.km} km'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _openEditor(r),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _delete(r),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}