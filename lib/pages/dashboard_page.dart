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
  SupabaseClient get sb => Supabase.instance.client;
  int? routesCount;
  bool loadingRoutes = false;
  String? routesError;

  bool loadingRecent = false;
  String? recentError;
  List<Map<String, dynamic>> recentOffers = [];

  @override
  void initState() {
    super.initState();

    _loadRoutesCount();
    _loadRecentOffers();

    // Auto refresh når draft lagres / slettes
    OfferStorageService.recentOffersRefresh.addListener(_onRecentRefresh);
  }

  @override
  void dispose() {
    OfferStorageService.recentOffersRefresh.removeListener(_onRecentRefresh);
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
      final client = Supabase.instance.client;
      final data = await client.from('routes_all').select('id');

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
  // RECENT OFFERS
  // ------------------------------------------------------------
  Future<void> _loadRecentOffers() async {
    setState(() {
      loadingRecent = true;
      recentError = null;
    });

    try {
      final items =
          await OfferStorageService.loadRecentOffers(limit: 30);

      if (!mounted) return;

      setState(() {
        recentOffers = items;
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
  Future<void> _confirmDeleteDraft(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete draft"),
        content: Text(
          "Are you sure you want to permanently delete:\n\n$title",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
              rootNavigator: true,
            ).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
              rootNavigator: true,
            ).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // 1️⃣ Slett kalender-rader først
await sb
    .from('samletdata')
    .delete()
    .eq('draft_id', id);

// 2️⃣ Slett selve draftet
await OfferStorageService.deleteDraft(id);

if (!mounted) return;

// 3️⃣ Feedback til bruker
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text("Draft deleted")),
);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Draft deleted")),
    );
  }

  // ------------------------------------------------------------
  // FORMAT DATE
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
                subtitle: "Companies, contacts and productions",
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
                border: Border.all(color: cs.outlineVariant),
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
                            ?.copyWith(fontWeight: FontWeight.w900),
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
                            Divider(color: cs.outlineVariant),
                        itemBuilder: (_, i) {
                          final row = recentOffers[i];

                          final id =
                              row['id']?.toString() ?? '';

                          final production =
                              (row['production'] ?? '—').toString();

                          final company =
                              (row['company'] ?? '—').toString();

                          final createdBy =
                              row['created_name']?.toString() ??
                                  'Unknown';

                          final updatedBy =
                              row['updated_name']?.toString() ??
                                  'Unknown';

                          final updatedDate = _fmtDateTime(
                            row['updated_at'] ??
                                row['created_at'],
                          );

                          return ListTile(
                            contentPadding: EdgeInsets.zero,

                            title: Text(
                              production,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),

                            subtitle: Text(
                              "$company • $updatedDate\n"
                              "Created: $createdBy • Updated: $updatedBy",
                            ),

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