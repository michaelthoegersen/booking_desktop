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

  TextEditingController _kmCtrl(Map<String, dynamic> row, String field) =>
      TextEditingController(
        text: row[field] != null
            ? (row[field] as num).toDouble().toStringAsFixed(1)
            : '',
      );

  Future<void> _editRoute(Map<String, dynamic> row) async {
    final fromCtrl = TextEditingController(text: row['from_place']);
    final toCtrl = TextEditingController(text: row['to_place']);
    final totalKmCtrl = TextEditingController(
      text: row['distance_total_km']?.toString() ?? '',
    );
    final ferryCtrl = TextEditingController(
      text: row['ferry_name']?.toString() ?? '',
    );

    // Per-country km controllers
    final seCtrl  = _kmCtrl(row, 'km_se');
    final dkCtrl  = _kmCtrl(row, 'km_dk');
    final deCtrl  = _kmCtrl(row, 'km_de');
    final beCtrl  = _kmCtrl(row, 'km_be');
    final plCtrl  = _kmCtrl(row, 'km_pl');
    final atCtrl  = _kmCtrl(row, 'km_at');
    final hrCtrl  = _kmCtrl(row, 'km_hr');
    final siCtrl  = _kmCtrl(row, 'km_si');

    bool noDDrive = (row['no_ddrive'] as bool?) ?? false;

    final double? currentKm =
        double.tryParse(row['distance_total_km']?.toString() ?? '');
    final bool isLongRoute = (currentKm ?? 0) >= 600;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: const Text("Edit route"),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: fromCtrl,
                        decoration: const InputDecoration(labelText: "From"),
                      ),
                      TextField(
                        controller: toCtrl,
                        decoration: const InputDecoration(labelText: "To"),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: totalKmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: "Total km"),
                      ),
                      TextField(
                        controller: ferryCtrl,
                        decoration: const InputDecoration(
                          labelText: "Ferry name (optional)",
                          hintText: "e.g. Puttgarden–Rødby",
                        ),
                      ),
                      if (isLongRoute) ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: noDDrive,
                          onChanged: (v) =>
                              setLocalState(() => noDDrive = v ?? false),
                          title: const Text("No D.Drive"),
                          subtitle: const Text(
                            "Route km ≥ 600 but should not trigger D.Drive",
                            style: TextStyle(fontSize: 12),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        "Km per land",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _countryKmField("SE", seCtrl),
                          _countryKmField("DK", dkCtrl),
                          _countryKmField("DE", deCtrl),
                          _countryKmField("BE", beCtrl),
                          _countryKmField("PL", plCtrl),
                          _countryKmField("AT", atCtrl),
                          _countryKmField("HR", hrCtrl),
                          _countryKmField("SI", siCtrl),
                        ],
                      ),
                    ],
                  ),
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
      },
    );

    // Dispose country km controllers
    for (final c in [seCtrl, dkCtrl, deCtrl, beCtrl, plCtrl, atCtrl, hrCtrl, siCtrl]) {
      c.dispose();
    }

    if (ok != true) return;

    double? parseKm(String text) {
      final v = double.tryParse(text.replaceAll(',', '.'));
      return (v != null && v > 0) ? v : null;
    }

    final km = double.tryParse(totalKmCtrl.text.replaceAll(',', '.'));

    await sb.from('routes_all').upsert(
      {
        'from_place': fromCtrl.text.trim(),
        'to_place': toCtrl.text.trim(),
        'distance_total_km': km,
        'ferry_name': ferryCtrl.text.trim().isEmpty
            ? null
            : ferryCtrl.text.trim(),
        'no_ddrive': isLongRoute ? noDDrive : false,
        'km_se': parseKm(seCtrl.text),
        'km_dk': parseKm(dkCtrl.text),
        'km_de': parseKm(deCtrl.text),
        'km_be': parseKm(beCtrl.text),
        'km_pl': parseKm(plCtrl.text),
        'km_at': parseKm(atCtrl.text),
        'km_hr': parseKm(hrCtrl.text),
        'km_si': parseKm(siCtrl.text),
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

  Widget _countryKmField(String label, TextEditingController ctrl) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: "km",
          isDense: true,
        ),
      ),
    );
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
                Row(
                  children: [
                    Text("Total: ${r['distance_total_km'] ?? '-'} km"),
                    if ((r['no_ddrive'] as bool?) == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: const Text(
                          "No D.Drive",
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
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
                    _kmChip("SE", r['km_se']),
                    _kmChip("DK", r['km_dk']),
                    _kmChip("DE", r['km_de']),
                    _kmChip("BE", r['km_be']),
                    _kmChip("PL", r['km_pl']),
                    _kmChip("AT", r['km_at']),
                    _kmChip("HR", r['km_hr']),
                    _kmChip("SI", r['km_si']),
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