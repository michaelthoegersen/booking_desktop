import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/route_result.dart';
import '../services/routes_service.dart';
import 'route_edit_dialog.dart';

class RoutesAdminPage extends StatefulWidget {
  const RoutesAdminPage({super.key});

  @override
  State<RoutesAdminPage> createState() => _RoutesAdminPageState();
}

class _RoutesAdminPageState extends State<RoutesAdminPage> {
  final RoutesService _service = RoutesService();

  List<RouteResult> _routes = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ------------------------------------------------------------
  // LOAD (SAFE)
  // ------------------------------------------------------------
  Future<void> _load() async {
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      final res = await _service.getAllRoutes();

      final list = <RouteResult>[];

      for (final e in res) {
        try {
          list.add(RouteResult.fromMap(e));
        } catch (err) {
          debugPrint('PARSE ERROR: $err');
        }
      }

      if (!mounted) return;

      setState(() {
        _routes = list;
      });
    } catch (e, st) {
      debugPrint('LOAD ERROR: $e');
      debugPrint(st.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // OPEN EDITOR
  // ------------------------------------------------------------
  Future<void> _openEditor([RouteResult? route]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return RouteEditDialog(
          route: route,
          service: _service,
        );
      },
    );

    if (changed == true) {
      await _load();
    }
  }

  // ------------------------------------------------------------
  // DELETE
  // ------------------------------------------------------------
  Future<void> _delete(RouteResult route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete route'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _service.deleteRoute(route.id);

      if (!mounted) return;

      await _load();
    } catch (e, st) {
      debugPrint('DELETE ERROR: $e');
      debugPrint(st.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
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

      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_routes.isEmpty) {
      return const Center(
        child: Text('No routes found'),
      );
    }

    return SafeArea(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _routes.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final r = _routes[i];

          return ListTile(
            leading: const Icon(Icons.route),

            title: Text('${r.from} → ${r.to}'),

            subtitle: Text(
              '${r.km.toStringAsFixed(1)} km',
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _openEditor(r),
                ),

                IconButton(
                  icon: const Icon(Icons.delete_outline),
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