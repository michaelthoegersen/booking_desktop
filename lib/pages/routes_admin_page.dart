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

  final TextEditingController _searchCtrl = TextEditingController();
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
  // LOAD ROUTES
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
      _filteredRoutes =
          _search.isEmpty ? routes : _applySearchInternal(_search);

    } catch (e) {
      error = e.toString();
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
      _filteredRoutes =
          q.isEmpty ? routes : _applySearchInternal(q);
    });
  }

  List<Map<String, dynamic>> _applySearchInternal(String q) {
    return routes.where((r) {
      final from = (r['from_place'] ?? '').toString().toLowerCase();
      final to = (r['to_place'] ?? '').toString().toLowerCase();
      return from.contains(q) || to.contains(q);
    }).toList();
  }

  // =================================================
  // EDIT ROUTE
  // =================================================

  Future<void> _editRoute(Map<String, dynamic> row) async {
    final fromCtrl = TextEditingController(text: row['from_place']);
    final toCtrl = TextEditingController(text: row['to_place']);
    final kmCtrl = TextEditingController(
      text: row['distance_total_km']?.toString() ?? '',
    );
    final ferryCtrl = TextEditingController(
      text: row['ferry_name']?.toString() ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Edit route"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fromCtrl,
                  decoration: const InputDecoration(labelText: "From"),
                ),
                TextField(
                  controller: toCtrl,
                  decoration: const InputDecoration(labelText: "To"),
                ),
                TextField(
                  controller: kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Total km"),
                ),
                TextField(
                  controller: ferryCtrl,
                  decoration: const InputDecoration(
                    labelText: "Ferry name (optional)",
                    hintText: "e.g. Puttgarden–Rødby",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final km =
        double.tryParse(kmCtrl.text.replaceAll(',', '.'));

    await sb.from('routes_all').upsert(
      {
        'from_place': fromCtrl.text.trim(),
        'to_place': toCtrl.text.trim(),
        'distance_total_km': km,
        'ferry_name': ferryCtrl.text.trim().isEmpty
            ? null
            : ferryCtrl.text.trim(),
      },
      onConflict: 'from_place,to_place',
    );

    await _loadRoutes();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route updated")),
      );
    }
  }

  // =================================================
  // ADD / EDIT FERRIES (POPUP)
  // =================================================

  Future<void> _openAddFerryPopup() async {
    final nameCtrl = TextEditingController();
    final baseCtrl = TextEditingController();
    final trailerCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: "EUR");
    bool active = true;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Add ferry"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Ferry name",
                  ),
                ),
                TextField(
                  controller: baseCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Base price",
                  ),
                ),
                TextField(
                  controller: trailerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Trailer price",
                  ),
                ),
                TextField(
                  controller: currencyCtrl,
                  decoration: const InputDecoration(
                    labelText: "Currency",
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: active,
                  onChanged: (v) => active = v ?? true,
                  title: const Text("Active"),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    await sb.from('ferries').insert({
      'name': nameCtrl.text.trim(),
      'base_price':
          double.tryParse(baseCtrl.text.replaceAll(',', '.')),
      'trailer_price':
          double.tryParse(trailerCtrl.text.replaceAll(',', '.')),
      'currency': currencyCtrl.text.trim(),
      'active': active,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ferry saved")),
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
      label: Text("$code: ${km.toStringAsFixed(0)} km",
          style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.blueGrey.shade50,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            icon: const Icon(Icons.directions_boat),
            tooltip: "Manage ferries",
            onPressed: _openAddFerryPopup,
          ),
          IconButton(
            onPressed: _loadRoutes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: "Search from / to…",
                prefixIcon: Icon(Icons.search),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Text(error!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_filteredRoutes.isEmpty) {
      return const Center(child: Text("No routes"));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredRoutes.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final r = _filteredRoutes[i];

        return Card(
          child: ListTile(
            title: Text(
              "${r['from_place']} → ${r['to_place']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total: ${r['distance_total_km'] ?? '-'} km"),
                const SizedBox(height: 4),
                Text(
                  "Ferry: ${r['ferry_name'] ?? '—'}",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: r['ferry_name'] == null
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
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
                    _kmChip("BE", r['km_be']),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editRoute(r),
            ),
          ),
        );
      },
    );
  }
}