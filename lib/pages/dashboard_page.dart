import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import '../services/offer_storage_service.dart';
import '../state/active_company.dart';
import '../widgets/bus_map_widget.dart';
import '../models/bus_position.dart';
import '../data/city_coords.dart';
import '../services/openroute_routing.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  String? _extractTime(String? raw) {
  if (raw == null) return null;

  final match = RegExp(r'(\d{2}:\d{2})').firstMatch(raw);

  return match?.group(1);
}

  DateTime? _parseDateTime(String date, String? time) {
  try {
    final safeTime =
        (time == null || time.trim().isEmpty)
            ? "00:00"
            : time.trim();

    return DateTime.parse("$date $safeTime");
  } catch (e) {
    debugPrint("⛔ Date parse failed: $date $time");
    return null;
  }

}
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

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';


  // ------------------------------------------------------------
  // BUS LOCATIONS (TODAY)
  // ------------------------------------------------------------

  Map<String, BusPosition> busLocationsToday = {};

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

    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }


  @override
  void dispose() {
    OfferStorageService.recentOffersRefresh
        .removeListener(_onRecentRefresh);

    _searchCtrl.dispose();

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
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final res = await sb
        .from('samletdata')
        .select('kilde, sted, dato, getin, produksjon')
        .lte('dato', todayStr)
        .order('dato', ascending: false);

    final rows = List<Map<String, dynamic>>.from(res);

    debugPrint("BUS ROWS: ${rows.length}");

    // Gruppér per buss
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final r in rows) {
      final bus = r['kilde']?.toString();
      if (bus == null) continue;

      grouped.putIfAbsent(bus, () => []);
      grouped[bus]!.add(r);
    }

    final Map<String, BusPosition> result = {};

    // Behandle hver buss
    await Future.forEach(
      grouped.entries,
      (MapEntry<String, List<Map<String, dynamic>>> entry) async {
        final bus = entry.key;
        final list = entry.value;

        if (list.isEmpty) return;

        final latest = list[0];

        final place = latest['sted']?.toString();
        final date = latest['dato']?.toString();
        final raw = latest['getin']?.toString();
        final production = latest['produksjon']?.toString();

        if (place == null || date == null) return;

        // Buss er ikke ute i dag — ikke vis på kart
        if (date != todayStr) return;

        // Kun én rad → statisk
        if (list.length < 2 || raw == null || raw.isEmpty) {
          result[bus] = BusPosition(place: place, production: production);
          return;
        }

        final prev = list[1];

        final prevPlace = prev['sted']?.toString();
        final prevDate = prev['dato']?.toString();
        final prevRaw = prev['getin']?.toString();

        if (prevPlace == null || prevDate == null) {
          result[bus] = BusPosition(place: place, production: production);
          return;
        }

        final startTime =
            _parseDateTime(prevDate, _extractTime(prevRaw));

        final endTime =
            _parseDateTime(date, _extractTime(raw));

        if (startTime == null || endTime == null) {
          result[bus] = BusPosition(place: place, production: production);
          return;
        }

        final now = DateTime.now();

        // Ikke underveis
        if (!now.isAfter(startTime) || !now.isBefore(endTime)) {
          result[bus] = BusPosition(place: place, production: production);
          return;
        }

        final from = cityCoords[prevPlace.toLowerCase()];
        final to = cityCoords[place.toLowerCase()];

        if (from == null || to == null) {
          result[bus] = BusPosition(place: place, production: production);
          return;
        }

        final total = endTime.difference(startTime).inSeconds;
        final passed = now.difference(startTime).inSeconds;

        final p = passed / total;

        // Hent rute
        List<LatLng> route = [];

        try {
          route = await OpenRouteService.getRoute(from, to);
        } catch (e) {
          debugPrint("⚠️ Routing failed for $bus: $e");
        }

        // Fallback → rett linje
        if (route.isEmpty) {
          debugPrint("⚠️ Using linear fallback for $bus");

          final lat =
              from.latitude + (to.latitude - from.latitude) * p;

          final lng =
              from.longitude + (to.longitude - from.longitude) * p;

          result[bus] = BusPosition(
            livePos: LatLng(lat, lng),
            production: production,
          );

          return;
        }

        // Finn punkt på ruten
        final index =
            (p * (route.length - 1))
                .clamp(0, route.length - 1)
                .toInt();

        final pos = route[index];

        result[bus] = BusPosition(livePos: pos, production: production);
      },
    );

    if (!mounted) return;

    setState(() {
      busLocationsToday = result;
    });
  } catch (e, st) {
    debugPrint("BUS MAP ERROR: $e");
    debugPrint(st.toString());

    if (!mounted) return;

    setState(() {
      busLocationError = e.toString();
      busLocationsToday = {};
    });
  } finally {
    if (mounted) {
      setState(() => loadingBusLocations = false);
    }
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
  // ARCHIVE DRAFT (FROM DASHBOARD)
  // ------------------------------------------------------------

  Future<void> _archiveDraft(String id, String production) async {
    // Ask whether to also remove calendar entries
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Archive "$production"?'),
        content: const Text(
          'Do you also want to remove this draft from the calendar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop('keep'),
            child: const Text('Keep in calendar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop('remove'),
            child: const Text('Remove from calendar'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      if (result == 'remove') {
        await sb.from('samletdata').delete().eq('draft_id', id);
      }
      await OfferStorageService.archiveDraft(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archived "$production"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // CHANGE CREATOR
  // ------------------------------------------------------------

  Future<void> _changeCreator(String offerId, String currentName) async {
    final sb = Supabase.instance.client;
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return;

    final profilesRes = await sb.rpc(
      'get_company_member_profiles',
      params: {'p_company_id': companyId},
    );

    final profiles = (profilesRes as List).cast<Map<String, dynamic>>();

    if (!mounted || profiles.isEmpty) return;

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change creator'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: profiles.length,
            itemBuilder: (_, i) {
              final p = profiles[i];
              final name = p['name']?.toString() ?? 'Unknown';
              final isCurrent = name == currentName;
              return ListTile(
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: isCurrent
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (picked == null) return;

    await sb
        .from('offers')
        .update({'created_by': picked['id']})
        .eq('id', offerId);

    _loadRecentOffers();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Creator changed to ${picked['name']}')),
      );
    }
  }

  // ------------------------------------------------------------
  // BUS MAP WIDGET
  // ------------------------------------------------------------

  // ------------------------------------------------------------
  // PDF DIALOG
  // ------------------------------------------------------------

  Future<void> _showPdfDialog(BuildContext context, String pdfUrl) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _PdfViewDialog(pdfUrl: pdfUrl),
    );
  }

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

    case 'invoiced': // ✅ NY
      return Colors.blue.shade400;

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

                    const SizedBox(width: 16),

                    SizedBox(
                      width: 240,
                      height: 36,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search offers…',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          isDense: true,
                        ),
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
  child: Builder(
    builder: (context) {
      final filtered = _searchQuery.isEmpty
          ? recentOffers
          : recentOffers.where((row) {
              final prod = (row['production'] ?? '').toString().toLowerCase();
              final comp = (row['company'] ?? '').toString().toLowerCase();
              return prod.contains(_searchQuery) || comp.contains(_searchQuery);
            }).toList();

      return ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(color: cs.outlineVariant),
        itemBuilder: (_, i) {
          final row = filtered[i];

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
        subtitle: GestureDetector(
          onTap: id.isEmpty
              ? null
              : () => _changeCreator(id, createdBy),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Created: '),
                TextSpan(
                  text: createdBy,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
                TextSpan(text: ' • Updated: $updatedBy\n'),
                TextSpan(text: 'Last update: $updatedDate'),
              ],
            ),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
        ),

        // PDF + DELETE
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (row['pdf_path'] != null)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                tooltip: 'View PDF',
                onPressed: () => _showPdfDialog(
                  context,
                  OfferStorageService.getPdfUrl(
                    row['pdf_path'] as String,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archive',
              onPressed: id.isEmpty
                  ? null
                  : () => _archiveDraft(id, production),
            ),
          ],
        ),

        onTap: id.isEmpty
            ? null
            : () => context.go("/new/$id"),
      );
        },
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

// ============================================================
// PDF VIEW DIALOG
// ============================================================

class _PdfViewDialog extends StatefulWidget {
  final String pdfUrl;
  const _PdfViewDialog({required this.pdfUrl});

  @override
  State<_PdfViewDialog> createState() => _PdfViewDialogState();
}

class _PdfViewDialogState extends State<_PdfViewDialog> {
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final res = await http.get(Uri.parse(widget.pdfUrl));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      setState(() {
        _pdfBytes = res.bodyBytes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      child: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.picture_as_pdf, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PDF Preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 48),
                              const SizedBox(height: 12),
                              Text('Failed to load PDF: $_error'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _loading = true;
                                    _error = null;
                                    _pdfBytes = null;
                                  });
                                  _loadPdf();
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : PdfPreview(
                          build: (_) async => _pdfBytes!,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          allowPrinting: true,
                          allowSharing: true,
                          maxPageWidth: 800,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}