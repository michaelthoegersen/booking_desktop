import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoutesAdminPage extends StatefulWidget {
  const RoutesAdminPage({super.key});

  @override
  State<RoutesAdminPage> createState() => _RoutesAdminPageState();
}

class _RoutesAdminPageState extends State<RoutesAdminPage> {
  final sb = Supabase.instance.client;

  bool loading = true;
  String? error;

  List<Map<String, dynamic>> routes = [];
  List<Map<String, dynamic>> _filteredRoutes = [];

  final TextEditingController _searchCtrl =
      TextEditingController();

  String _search = '';

  // =================================================
  // INIT
  // =================================================

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // =================================================
  // LOAD
  // =================================================

  Future<void> _loadRoutes() async {
  setState(() {
    loading = true;
    error = null;
  });

  try {
    final List<Map<String, dynamic>> all = [];

    int from = 0;
    const int limit = 1000;

    while (true) {
      final res = await sb
          .from('routes_all')
          .select()
          .order('from_place')
          .range(from, from + limit - 1);

      final batch = List<Map<String, dynamic>>.from(res);

      if (batch.isEmpty) break;

      all.addAll(batch);

      if (batch.length < limit) break;

      from += limit;
    }

    routes = all;

    debugPrint("ROUTES TOTAL: ${routes.length}");

    if (_search.isEmpty) {
      _filteredRoutes = routes;
    } else {
      _applySearch(_search);
    }

  } catch (e, st) {
    error = e.toString();
    debugPrint("LOAD ERROR: $e");
    debugPrint("$st");
  }

  if (mounted) {
    setState(() => loading = false);
  }
}

  // =================================================
  // SEARCH
  // =================================================

  void _applySearch(String value) {
    final q = value.trim().toLowerCase();

    setState(() {
      _search = q;

      if (q.isEmpty) {
        _filteredRoutes = routes;
      } else {
        _filteredRoutes = routes.where((r) {
          final from =
              (r['from_place'] ?? '').toString().toLowerCase();

          final to =
              (r['to_place'] ?? '').toString().toLowerCase();

          return from.contains(q) || to.contains(q);
        }).toList();
      }
    });
  }

  // =================================================
  // DELETE
  // =================================================

  Future<void> _deleteRoute(
    String from,
    String to,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete route"),
        content: Text("Delete route:\n$from → $to ?"),
        actions: [

          // CANCEL
          TextButton(
            onPressed: () {
              Navigator.of(
                dialogContext,
                rootNavigator: true,
              ).pop(false);
            },
            child: const Text("Cancel"),
          ),

          // DELETE
          FilledButton(
            onPressed: () {
              Navigator.of(
                dialogContext,
                rootNavigator: true,
              ).pop(true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await sb
          .from('routes_all')
          .delete()
          .eq('from_place', from)
          .eq('to_place', to);

      await _loadRoutes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route deleted")),
      );

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Delete failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =================================================
  // EDIT
  // =================================================

  Future<void> _editRoute(Map<String, dynamic> row) async {

    final fromCtrl =
        TextEditingController(text: row['from_place']);

    final toCtrl =
        TextEditingController(text: row['to_place']);

    final kmCtrl = TextEditingController(
      text: row['distance_total_km']?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,

      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Edit route"),

          content: SizedBox(
            width: 400,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [

                TextField(
                  controller: fromCtrl,
                  decoration:
                      const InputDecoration(labelText: "From"),
                ),

                TextField(
                  controller: toCtrl,
                  decoration:
                      const InputDecoration(labelText: "To"),
                ),

                TextField(
                  controller: kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "Total km"),
                ),
              ],
            ),
          ),

          actions: [

            // CANCEL
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                  rootNavigator: true,
                ).pop(false);
              },
              child: const Text("Cancel"),
            ),

            // SAVE
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                  rootNavigator: true,
                ).pop(true);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final km =
        double.tryParse(kmCtrl.text.replaceAll(',', '.'));

    try {
      await sb.from('routes_all').upsert(
        {
          'from_place': fromCtrl.text.trim(),
          'to_place': toCtrl.text.trim(),
          'distance_total_km': km,
        },
        onConflict: 'from_place,to_place',
      );

      await _loadRoutes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route updated")),
      );

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Update failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =================================================
  // KM CHIP
  // =================================================

  Widget _kmChip(String code, dynamic value) {
    if (value == null) return const SizedBox();

    final km = (value as num?)?.toDouble() ?? 0;

    if (km <= 0) return const SizedBox();

    return Chip(
      label: Text(
        "$code: ${km.toStringAsFixed(1)} km",
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: Colors.blueGrey.shade50,
      materialTapTargetSize:
          MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  // =================================================
  // UI
  // =================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(
        title: const Text("Route Manager"),

        actions: [

          IconButton(
            onPressed: _loadRoutes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: Column(
        children: [

          // 🔍 SEARCH
          Padding(
            padding: const EdgeInsets.all(12),

            child: TextField(
              controller: _searchCtrl,

              decoration: InputDecoration(
                hintText: "Search from / to…",
                prefixIcon: const Icon(Icons.search),

                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applySearch('');
                        },
                      )
                    : null,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              onChanged: _applySearch,
            ),
          ),

          const Divider(height: 1),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (error != null) {
      return Center(
        child: Text(
          error!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_filteredRoutes.isEmpty) {
      return const Center(
        child: Text("No routes"),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),

      itemCount: _filteredRoutes.length,

      separatorBuilder: (_, __) =>
          const Divider(),

      itemBuilder: (_, i) {

        final r = _filteredRoutes[i];

        final from = r['from_place'] ?? '';
        final to = r['to_place'] ?? '';
        final km = r['distance_total_km'];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),

          child: ListTile(

            title: Text(
              "$from → $to",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                const SizedBox(height: 4),

                Text("Total: ${km ?? '-'} km"),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 8,
                  runSpacing: 4,

                  children: [

                    _kmChip("DK", r['km_dk']),
                    _kmChip("DE", r['km_de']),
                    _kmChip("PL", r['km_pl']),
                    _kmChip("AT", r['km_at']),
                    _kmChip("HR", r['km_hr']),
                    _kmChip("SI", r['km_si']),
                  ],
                ),
              ],
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,

              children: [

                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: "Edit",
                  onPressed: () => _editRoute(r),
                ),

                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: "Delete",
                  color: Colors.red,
                  onPressed: () => _deleteRoute(from, to),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}