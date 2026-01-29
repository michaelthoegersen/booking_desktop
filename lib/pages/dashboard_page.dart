import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/action_tile.dart';
import '../services/offer_storage_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {

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
  // DATE CACHE (from → to per offer)
  // ------------------------------------------------------------

  final Map<String, String> _offerDateCache = {};


  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadRoutesCount();
    _loadRecentOffers();

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
// LOAD RECENT OFFERS (with status)
// ------------------------------------------------------------
Future<void> _loadRecentOffers() async {

  setState(() {
    loadingRecent = true;
    recentError = null;
  });

  try {

    // 1️⃣ Load drafts/offers
    final items =
        await OfferStorageService.loadRecentOffers(limit: 30);

    if (!mounted) return;

    // 2️⃣ Collect ids
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

    // 3️⃣ Load status from samletdata
    final statusRows = await sb
        .from('samletdata')
        .select('draft_id, status')
        .inFilter('draft_id', ids);

    final statusMap = <String, String>{};

    for (final r in statusRows) {
      final id = r['draft_id']?.toString();
      final status = r['status']?.toString();

      if (id != null && status != null && status.isNotEmpty) {
        statusMap[id] = status;
      }
    }

    // 4️⃣ Merge status into offers
    final merged = items.map((row) {
      final id = row['id']?.toString();

      return {
        ...row,
        'status': statusMap[id] ?? '',
      };
    }).toList();

    // 5️⃣ Update UI
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
  // DELETE DRAFT
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


    // Delete calendar rows
    await sb
        .from('samletdata')
        .delete()
        .eq('draft_id', id);


    // Delete draft
    await OfferStorageService.deleteDraft(id);


    if (!mounted) return;


    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Draft deleted")),
    );
  }


  // ------------------------------------------------------------
  // LOAD DATE RANGE PER OFFER
  // ------------------------------------------------------------

  Future<String> _getOfferDateRange(String offerId) async {

    // Use cache
    if (_offerDateCache.containsKey(offerId)) {
      return _offerDateCache[offerId]!;
    }

    try {

      final res = await sb
          .from('samletdata')
          .select('dato')
          .eq('draft_id', offerId)
          .order('dato');


      final list = List<Map<String, dynamic>>.from(res);

      if (list.isEmpty) return '';


      final from =
          DateTime.parse(list.first['dato']);

      final to =
          DateTime.parse(list.last['dato']);


      final text =
          "${_fmtDate(from)} → ${_fmtDate(to)}";


      _offerDateCache[offerId] = text;

      return text;

    } catch (_) {

      return '';
    }
  }


  // ------------------------------------------------------------
  // FORMAT DATE (dd.MM.yyyy)
  // ------------------------------------------------------------

  String _fmtDate(DateTime d) {

    return "${d.day.toString().padLeft(2, '0')}"
        ".${d.month.toString().padLeft(2, '0')}"
        ".${d.year}";
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

      return "${d.day.toString().padLeft(2, '0')}"
          ".${d.month.toString().padLeft(2, '0')}"
          ".${d.year} "
          "${d.hour.toString().padLeft(2, '0')}"
          ":${d.minute.toString().padLeft(2, '0')}";

    } catch (_) {

      return "";
    }
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
      return Colors.grey;
  }
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

          // --------------------------------------------------
          // HEADER
          // --------------------------------------------------

          Text(
            "Welcome",

            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),


          const SizedBox(height: 6),


          Text(
            "Choose what you want to do.",

            style: TextStyle(color: cs.onSurfaceVariant),
          ),


          const SizedBox(height: 16),


          // --------------------------------------------------
          // ACTION TILES
          // --------------------------------------------------

          Wrap(
            spacing: 14,
            runSpacing: 14,

            children: [

              ActionTile(
                title: "New Offer",
                subtitle: "Create a new booking offer",
                icon: Icons.add_circle_outline,
                primary: true,
                onTap: () => context.go("/new"),
              ),

              ActionTile(
                title: "Edit Offer",
                subtitle: "Open and edit existing offers",
                icon: Icons.edit_note,
                onTap: () => context.go("/edit"),
              ),

              ActionTile(
                title: "Customers",
                subtitle:
                    "Companies, contacts and productions",
                icon: Icons.apartment_rounded,
                onTap: () => context.go("/customers"),
              ),

              ActionTile(
                title: "Settings",
                subtitle: "Language, export, templates",
                icon: Icons.settings,
                onTap: () => context.go("/settings"),
              ),
            ],
          ),


          const SizedBox(height: 18),


          // --------------------------------------------------
          // RECENT OFFERS
          // --------------------------------------------------

          Expanded(
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
                                fontWeight:
                                    FontWeight.w900),
                      ),

                      const Spacer(),

                      OutlinedButton.icon(
                        onPressed: loadingRecent
                            ? null
                            : _loadRecentOffers,

                        icon: const Icon(Icons.refresh),

                        label: const Text("Refresh"),
                      ),
                    ],
                  ),


                  const SizedBox(height: 12),


                  // ---------------- LOADING
                  if (loadingRecent)

                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )


                  // ---------------- EMPTY
                  else if (recentOffers.isEmpty)

                    const Expanded(
                      child: Center(
                        child: Text("No offers yet."),
                      ),
                    )


                  // ---------------- LIST
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

                          final id =
                              row['id']?.toString() ?? '';

                          final production =
                              (row['production'] ?? '—')
                                  .toString();

                          final company =
                              (row['company'] ?? '—')
                                  .toString();

                          final createdBy =
                              row['created_name']
                                      ?.toString() ??
                                  'Unknown';

                          final updatedBy =
                              row['updated_name']
                                      ?.toString() ??
                                  'Unknown';

                          final updatedDate =
                              _fmtDateTime(
                            row['updated_at'] ??
                                row['created_at'],
                          );
                          final status = row['status']?.toString() ?? '';

                          return FutureBuilder<String>(

                            future: id.isEmpty
                                ? null
                                : _getOfferDateRange(id),

                            builder: (context, snap) {

                              final dateRange =
                                  snap.data ?? '';


                              return ListTile(
  contentPadding: EdgeInsets.zero,

// =====================================================
// TITLE: Production + Company + Status (COMPACT)
// =====================================================
title: Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  mainAxisSize: MainAxisSize.min,

  children: [

    // ============================
    // Production
    // ============================
    Text(
      production,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    ),

    // ============================
    // Company
    // ============================
    if (company.isNotEmpty) ...[
      const SizedBox(width: 6),

      Text(
        "• $company",

        overflow: TextOverflow.ellipsis,

        style: const TextStyle(
          fontSize: 13,
          color: Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],

    // ============================
    // Status (right after company)
    // ============================
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

  // =====================================================
  // SUBTITLE: Date + Meta
  // =====================================================
  subtitle: RichText(
    text: TextSpan(
      style: Theme.of(context).textTheme.bodySmall,

      children: [

        // Date range
        if (dateRange.isNotEmpty)
          TextSpan(
            text: "📅 $dateRange\n",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),

        // Meta info
        TextSpan(
          text:
              "Created: $createdBy • Updated: $updatedBy\n"
              "Last update: $updatedDate",
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
          ),
        ),
      ],
    ),
  ),

  // =====================================================
  // DELETE BUTTON
  // =====================================================
  trailing: IconButton(
    icon: Icon(
      Icons.delete_outline,
      color: cs.error,
    ),

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