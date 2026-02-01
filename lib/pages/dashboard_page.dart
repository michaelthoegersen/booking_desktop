import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/offer_storage_service.dart';
import '../widgets/bus_map_widget.dart';
import 'dart:convert';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
// ------------------------------------------------------------
// CITY → COORDINATES (FOR MAP)
// ------------------------------------------------------------

  // ------------------------------------------------------------
  // SUPABASE
  // ------------------------------------------------------------

  SupabaseClient get sb => Supabase.instance.client;


  // ------------------------------------------------------------
  // ROUTES
  // ------------------------------------------------------------

  int? routesCount;
  bool loadingRoutes = false;
  String? routesError;


  // ------------------------------------------------------------
  // RECENT OFFERS
  // ------------------------------------------------------------

  bool loadingRecent = false;
  String? recentError;

  List<Map<String, dynamic>> recentOffers = [];


  // ------------------------------------------------------------
  // BUS LOCATIONS (TODAY)
  // ------------------------------------------------------------

  Map<String, String> busLocationsToday = {};

  bool loadingBusLocations = false;
  String? busLocationError;


  // ------------------------------------------------------------
  // DATE CACHE
  // ------------------------------------------------------------

  final Map<String, String> offerDateCache = {};


  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadRoutesCount();
    _loadRecentOffers();
    _loadBusLocationsToday();

    OfferStorageService.recentOffersRefresh
        .addListener(_onRecentRefresh);
  }


  @override
  void dispose() {
    OfferStorageService.recentOffersRefresh
        .removeListener(_onRecentRefresh);

    super.dispose();
  }


  void _onRecentRefresh() {
    _loadRecentOffers();
  }


  // ------------------------------------------------------------
  // ROUTES COUNT
  // ------------------------------------------------------------

  Future<void> _loadRoutesCount() async {

    setState(() {
      loadingRoutes = true;
      routesError = null;
    });

    try {

      final data =
          await sb.from('routes_all').select('id');

      setState(() {
        routesCount = (data as List).length;
      });

    } catch (e) {

      setState(() {
        routesError = e.toString();
        routesCount = null;
      });

    } finally {

      if (mounted) {
        setState(() => loadingRoutes = false);
      }
    }
  }


  // ------------------------------------------------------------
  // LOAD RECENT OFFERS
  // ------------------------------------------------------------

  Future<void> _loadRecentOffers() async {

  setState(() {
    loadingRecent = true;
    recentError = null;
  });

  try {

    // 1. Hent offers
    final items =
        await OfferStorageService.loadRecentOffers(limit: 200);

    if (!mounted) return;

    // 2. Samle alle id-er
    final ids = items
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toList();

    if (ids.isEmpty) {
      setState(() {
        recentOffers = items;
      });
      return;
    }

    // 3. Hent status fra samletdata
    final statusRows = await sb
        .from('samletdata')
        .select('draft_id, status')
        .inFilter('draft_id', ids);

    // 4. Lag map: id -> status
    final Map<String, String> statusMap = {};

    for (final r in statusRows) {

      final id = r['draft_id']?.toString();
      final status = r['status']?.toString();

      if (id != null &&
          status != null &&
          status.isNotEmpty) {

        statusMap[id] = status;
      }
    }

    // 5. Slå sammen status + offers
    final merged = items.map((row) {

      final id = row['id']?.toString();

      return {
        ...row,
        'status': statusMap[id] ?? '',
      };

    }).toList();

    // 6. Oppdater UI
    setState(() {
      recentOffers = merged;
    });

  } catch (e) {

    if (!mounted) return;

    setState(() {
      recentError = e.toString();
      recentOffers = [];
    });

  } finally {

    if (!mounted) return;

    setState(() => loadingRecent = false);
  }
}


  // ------------------------------------------------------------
  // LOAD BUS LOCATIONS (TODAY)
  // ------------------------------------------------------------

  Future<void> _loadBusLocationsToday() async {
  setState(() {
    loadingBusLocations = true;
    busLocationError = null;
  });

  try {
    final today = DateTime.now();

    final todayStr =
        "${today.year}-"
        "${today.month.toString().padLeft(2, '0')}-"
        "${today.day.toString().padLeft(2, '0')}";

    final res = await sb
        .from('samletdata')
        .select('kilde, sted')
        .eq('dato', todayStr);

    final rows = List<Map<String, dynamic>>.from(res);

    final Map<String, String> map = {};

    for (final r in rows) {
      final bus = r['kilde']?.toString().trim();
      final place = r['sted']?.toString().trim();

      if (bus == null || bus.isEmpty) continue;

      // Kun én per buss (første vinner)
      if (!map.containsKey(bus)) {
        map[bus] =
            (place == null || place.isEmpty)
                ? 'Linköping'
                : place;
      }
    }

    debugPrint("BUS MAP: $map"); // 👈 debug

    setState(() {
      busLocationsToday = map;
    });
  } catch (e) {
    debugPrint("BUS MAP ERROR: $e");

    setState(() {
      busLocationError = e.toString();
      busLocationsToday = {};
    });
  } finally {
    setState(() => loadingBusLocations = false);
  }
}


  // ------------------------------------------------------------
  // FORMAT DATETIME
  // ------------------------------------------------------------

  String _fmtDateTime(dynamic value) {

    try {

      if (value == null) return "";

      final d = value is DateTime
          ? value
          : DateTime.parse(value.toString());

      return
          "${d.day.toString().padLeft(2, '0')}."
          "${d.month.toString().padLeft(2, '0')}."
          "${d.year} "
          "${d.hour.toString().padLeft(2, '0')}:"
          "${d.minute.toString().padLeft(2, '0')}";

    } catch (_) {
      return "";
    }
  }

// ------------------------------------------------------------
// DELETE DRAFT (FROM DASHBOARD)
// ------------------------------------------------------------

Future<void> _confirmDeleteDraft(
  String id,
  String title,
) async {

  final ok = await showDialog<bool>(
    context: context,

    builder: (_) => AlertDialog(
      title: const Text("Delete draft"),

      content: Text(
        "Are you sure you want to permanently delete:\n\n$title",
      ),

      actions: [

        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true)
                  .pop(false),

          child: const Text("Cancel"),
        ),

        FilledButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true)
                  .pop(true),

          child: const Text("Delete"),
        ),
      ],
    ),
  );

  if (ok != true) return;

  try {

    // 1️⃣ Delete calendar rows
    await sb
        .from('samletdata')
        .delete()
        .eq('draft_id', id);

    // 2️⃣ Delete draft
    await OfferStorageService.deleteDraft(id);

    if (!mounted) return;

    // 3️⃣ Refresh list
    _loadRecentOffers();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Draft deleted"),
      ),
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
  // ------------------------------------------------------------
  // BUS MAP WIDGET
  // ------------------------------------------------------------

  // ------------------------------------------------------------
// BUS MAP SECTION (MapTiler)
// ------------------------------------------------------------

Widget _buildBusMapSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      // Header
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.map),

        title: const Text(
          "Bus locations today",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),

        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed:
              loadingBusLocations ? null : _loadBusLocationsToday,
        ),
      ),

      const SizedBox(height: 6),

      // 👇 MAP FYLLER RESTEN
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),

          child: BusMapWidget(
            busLocations: busLocationsToday,
            onRefresh: _loadBusLocationsToday,
          ),
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------
// STATUS COLOR
// ------------------------------------------------------------
Color _statusColor(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'draft':
      return Colors.purple.shade400;
    case 'inquiry':
      return Colors.orange.shade400;
    case 'confirmed':
      return Colors.green.shade500;
    default:
      return Colors.grey.shade400;
  }
}

String _buildRoundsTooltip(Map<String, dynamic> row) {

  dynamic raw = row['payload'] ?? row['offer_json'];

  if (raw == null) return "No rounds";

  final Map<String, dynamic> data =
      raw is String ? jsonDecode(raw) : raw;

  final rounds = data['rounds'] as List<dynamic>? ?? [];

  if (rounds.isEmpty) return "No rounds";

  final buffer = StringBuffer();

  String fmt(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}."
      "${d.month.toString().padLeft(2, '0')}."
      "${d.year}";

  for (int i = 0; i < rounds.length; i++) {

    final r = rounds[i];

    final entries = r['entries'] as List<dynamic>? ?? [];

    if (entries.isEmpty) continue;

    final dates = entries
        .map((e) => DateTime.tryParse(e['date'].toString()))
        .whereType<DateTime>()
        .toList()
      ..sort();

    if (dates.isEmpty) continue;

    buffer.writeln(
      "Round ${i + 1}: ${fmt(dates.first)} → ${fmt(dates.last)}",
    );
  }

  return buffer.isEmpty ? "No rounds" : buffer.toString().trim();
}
  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.all(18),

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        // =========================
        // BUS MAP (STORT)
        // =========================
        Expanded(
          flex: 10,
          child: _buildBusMapSection(),
        ),

        const SizedBox(height: 18),

        // =========================
        // RECENT OFFERS
        // =========================
        Expanded(
          flex: 10,

          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outlineVariant,
              ),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                // Header
                Row(
                  children: [

                    Text(
                      "Recent offers",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),

                    const Spacer(),

                    OutlinedButton.icon(
                      onPressed:
                          loadingRecent ? null : _loadRecentOffers,

                      icon: const Icon(Icons.refresh),
                      label: const Text("Refresh"),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // =========================
                // LIST
                // =========================
                if (loadingRecent)

                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )

                else if (recentOffers.isEmpty)

                  const Expanded(
                    child: Center(
                      child: Text("No offers yet."),
                    ),
                  )

                else

        Expanded(
  child: ListView.separated(

    itemCount: recentOffers.length,

    separatorBuilder: (_, __) =>
        Divider(
          color: cs.outlineVariant,
        ),

    itemBuilder: (_, i) {

      final row = recentOffers[i];

      final id = row['id']?.toString() ?? '';

      final production =
          row['production']?.toString() ?? '—';

      final company =
          row['company']?.toString() ?? '';

      final createdBy =
          row['created_name']?.toString() ?? 'Unknown';

      final updatedBy =
          row['updated_name']?.toString() ?? 'Unknown';

      final updatedDate = _fmtDateTime(
        row['updated_at'] ?? row['created_at'],
      );

      final status =
          row['status']?.toString() ?? '';

      // Tooltip-text
      final roundsTooltip = _buildRoundsTooltip(row);
      debugPrint("ROW KEYS: ${row.keys}");

      return ListTile(
        contentPadding: EdgeInsets.zero,

        // TITLE
        title: Tooltip(
          message: roundsTooltip,
          waitDuration: const Duration(milliseconds: 400),

          textStyle: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Colors.white,
          ),

          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,

            children: [

              Text(
                production,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),

              if (company.isNotEmpty) ...[
                const SizedBox(width: 6),

                Text(
                  "• $company",
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ],

              if (status.isNotEmpty) ...[
                const SizedBox(width: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),

                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(10),
                  ),

                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // SUBTITLE
        subtitle: Text(
          "Created: $createdBy • Updated: $updatedBy\n"
          "Last update: $updatedDate",

          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
          ),
        ),

        // DELETE
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: cs.error,
          ),

          tooltip: 'Delete draft',

          onPressed: id.isEmpty
              ? null
              : () => _confirmDeleteDraft(
                    id,
                    production,
                  ),
        ),

        onTap: id.isEmpty
            ? null
            : () => context.go("/new/$id"),
      );
    },
  ),
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