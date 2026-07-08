import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../localization/s.dart';
import '../services/km_se_updater.dart';
import '../widgets/route_popup_dialog.dart';

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
    // Support "Oslo - Gothenburg" style search: split on -/→/til and match from+to
    final parts = q.split(RegExp(r'\s*[-–—→]\s*|\s+til\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.length >= 2) {
      final qFrom = parts[0];
      final qTo = parts[1];
      return routes.where((r) {
        final from = (r['from_place'] ?? '').toString().toLowerCase();
        final to = (r['to_place'] ?? '').toString().toLowerCase();
        return from.contains(qFrom) && to.contains(qTo);
      }).toList();
    }

    return routes.where((r) {
      final from = (r['from_place'] ?? '').toString().toLowerCase();
      final to = (r['to_place'] ?? '').toString().toLowerCase();
      return from.contains(q) || to.contains(q);
    }).toList();
  }

  // =================================================
  // DELETE ROUTE
  // =================================================

  Future<void> _deleteRoute(Map<String, dynamic> row) async {
    final from = row['from_place'] ?? '';
    final to = row['to_place'] ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('delete')),
        content: Text('$from → $to'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('delete')),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('error')}: $e')),
        );
      }
    }
  }

  // =================================================
  // ADD NEW ROUTE (Route preview dialog with map)
  // =================================================

  Future<void> _addNewRoute() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const RoutePopupDialog(
        start: '',
        stops: [''],
      ),
    );

    if (saved == true) {
      await _loadRoutes();
    }
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

    // Parse existing extra to pre-check Ferry/Bridge
    final String existingExtra = (row['extra'] as String?)?.trim() ?? '';
    final String extraLower = existingExtra.toLowerCase();
    bool hasFerry = extraLower.contains('ferry');
    bool hasBridge = extraLower.contains('bridge');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final isNew = row['from_place'] == '' && row['to_place'] == '';
            return AlertDialog(
              title: Text(isNew ? S.t('addRoute') : S.t('editRoute')),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: fromCtrl,
                        decoration: InputDecoration(labelText: S.t('from')),
                      ),
                      TextField(
                        controller: toCtrl,
                        decoration: InputDecoration(labelText: S.t('to')),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: totalKmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: S.t('totalKm')),
                      ),
                      TextField(
                        controller: ferryCtrl,
                        decoration: InputDecoration(
                          labelText: S.t('ferryNameOptional'),
                          hintText: "e.g. Puttgarden–Rødby",
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: hasFerry,
                        onChanged: (v) =>
                            setLocalState(() => hasFerry = v ?? false),
                        title: Text(S.t('ferry')),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: hasBridge,
                        onChanged: (v) =>
                            setLocalState(() => hasBridge = v ?? false),
                        title: Text(S.t('bridge')),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (isLongRoute) ...[
                        CheckboxListTile(
                          value: noDDrive,
                          onChanged: (v) =>
                              setLocalState(() => noDDrive = v ?? false),
                          title: Text(S.t('noDDrive')),
                          subtitle: Text(
                            S.t('noDDriveDesc'),
                            style: TextStyle(fontSize: 12),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        S.t('kmPerCountry'),
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
                  child: Text(S.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(S.t('save')),
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

    // Build extra from checkboxes
    final extraParts = <String>[];
    if (hasFerry) extraParts.add('Ferry');
    if (hasBridge) extraParts.add('Bridge');
    final extraValue = extraParts.join('/');

    await sb.from('routes_all').upsert(
      {
        'from_place': fromCtrl.text.trim(),
        'to_place': toCtrl.text.trim(),
        'distance_total_km': km,
        'ferry_name': ferryCtrl.text.trim().isEmpty
            ? null
            : ferryCtrl.text.trim(),
        'extra': extraValue,
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
        SnackBar(content: Text(S.t('routeUpdated'))),
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

  Future<void> _openManageFerriesDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _FerryManagerDialog(sb: sb),
    );
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
        title: Text(S.t('routeManager')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_road),
            tooltip: S.t('addRoute'),
            onPressed: _addNewRoute,
          ),
          IconButton(
            icon: const Icon(Icons.directions_boat),
            tooltip: S.t('manageFerries'),
            onPressed: _openManageFerriesDialog,
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
              decoration: InputDecoration(
                hintText: S.t('searchFromTo'),
                prefixIcon: const Icon(Icons.search),
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
      return Center(child: Text(S.t('noRoutes')));
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
                    Text("${S.t('total')}: ${r['distance_total_km'] ?? '-'} km"),
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
                        child: Text(
                          S.t('noDDrive'),
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "${S.t('ferry')}: ${r['ferry_name'] ?? '—'}",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: r['ferry_name'] == null
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
                if (((r['extra'] as String?)?.trim() ?? '').isNotEmpty)
                  Text(
                    "${S.t('extra')}: ${r['extra']}",
                    style: const TextStyle(fontSize: 12),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editRoute(r),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteRoute(r),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================
// FERRY MANAGER DIALOG — list, add, edit, delete
// =============================================================

class _FerryManagerDialog extends StatefulWidget {
  final SupabaseClient sb;
  const _FerryManagerDialog({required this.sb});

  @override
  State<_FerryManagerDialog> createState() => _FerryManagerDialogState();
}

class _FerryManagerDialogState extends State<_FerryManagerDialog> {
  List<Map<String, dynamic>> _ferries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFerries();
  }

  Future<void> _loadFerries() async {
    setState(() => _loading = true);
    final res = await widget.sb
        .from('ferries')
        .select()
        .order('name');
    _ferries = List<Map<String, dynamic>>.from(res);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addOrEditFerry([Map<String, dynamic>? existing]) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final baseCtrl = TextEditingController(
      text: existing?['base_price']?.toString() ?? '',
    );
    final trailerCtrl = TextEditingController(
      text: existing?['trailer_price']?.toString() ?? '',
    );
    final currencyCtrl = TextEditingController(
      text: existing?['currency'] ?? 'EUR',
    );
    bool active = (existing?['active'] as bool?) ?? true;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing != null
                  ? S.t('editFerry')
                  : S.t('addFerry')),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: S.t('ferryName'),
                      ),
                    ),
                    TextField(
                      controller: baseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: S.t('basePrice'),
                      ),
                    ),
                    TextField(
                      controller: trailerCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: S.t('trailerPrice'),
                      ),
                    ),
                    TextField(
                      controller: currencyCtrl,
                      decoration: InputDecoration(
                        labelText: S.t('currency'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: active,
                      onChanged: (v) => setLocal(() => active = v ?? true),
                      title: Text(S.t('active')),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(S.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(S.t('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final data = {
      'name': nameCtrl.text.trim(),
      'base_price': double.tryParse(baseCtrl.text.replaceAll(',', '.')),
      'trailer_price': double.tryParse(trailerCtrl.text.replaceAll(',', '.')),
      'currency': currencyCtrl.text.trim(),
      'active': active,
    };

    if (existing != null) {
      await widget.sb
          .from('ferries')
          .update(data)
          .eq('id', existing['id']);
    } else {
      await widget.sb.from('ferries').insert(data);
    }

    await _loadFerries();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('ferrySaved'))),
      );
    }
  }

  Future<void> _deleteFerry(Map<String, dynamic> ferry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('delete')),
        content: Text(ferry['name'] ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await widget.sb.from('ferries').delete().eq('id', ferry['id']);
    await _loadFerries();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('ferryDeleted'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(S.t('manageFerries'))),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: S.t('addFerry'),
            onPressed: () => _addOrEditFerry(),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ferries.isEmpty
                ? Center(child: Text(S.t('noFerries')))
                : ListView.separated(
                    itemCount: _ferries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final f = _ferries[i];
                      final base = f['base_price'];
                      final trailer = f['trailer_price'];
                      final currency = f['currency'] ?? '';
                      final isActive = (f['active'] as bool?) ?? true;

                      return ListTile(
                        leading: Icon(
                          Icons.directions_boat,
                          color: isActive ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          f['name'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isActive ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          "${S.t('basePrice')}: ${base ?? '—'} $currency  ·  "
                          "${S.t('trailerPrice')}: ${trailer ?? '—'} $currency"
                          "${isActive ? '' : '  (inactive)'}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _addOrEditFerry(f),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              onPressed: () => _deleteFerry(f),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t('close')),
        ),
      ],
    );
  }
}