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

    // ✅ Auto-refresh recent offers når draft lagres
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
        setState(() {
          loadingRoutes = false;
        });
      }
    }
  }

  Future<void> _loadRecentOffers() async {
    setState(() {
      loadingRecent = true;
      recentError = null;
    });

    try {
      final items = await OfferStorageService.loadRecentOffers(limit: 30);
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
      setState(() {
        loadingRecent = false;
      });
    }
  }

  String _fmtDateTime(dynamic value) {
    try {
      if (value == null) return "";
      if (value is DateTime) {
        return "${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}";
      }
      final d = DateTime.parse(value.toString());
      return "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";
    } catch (_) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

          // ------------------------------------------------------------
          // ACTION TILES
          // ------------------------------------------------------------
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

          // ------------------------------------------------------------
          // ROUTES COUNT (SUPABASE STATUS)
          // ------------------------------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.alt_route_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Routes in database",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      if (loadingRoutes)
                        Text("Loading…", style: TextStyle(color: cs.onSurfaceVariant))
                      else if (routesError != null)
                        Text(
                          "Error: $routesError",
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          routesCount == null
                              ? "—"
                              : "$routesCount route(s) found in routes_all",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: loadingRoutes ? null : _loadRoutesCount,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh"),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ------------------------------------------------------------
          // RECENT OFFERS (LIVE SUPABASE)
          // ------------------------------------------------------------
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
                        onPressed: loadingRecent ? null : _loadRecentOffers,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Refresh"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (loadingRecent)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text("Loading offers…"),
                          ],
                        ),
                      ),
                    )
                  else if (recentError != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          "Error loading offers:\n$recentError",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else if (recentOffers.isEmpty)
                    const Expanded(
                      child: Center(child: Text("No offers yet.")),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: recentOffers.length,
                        separatorBuilder: (_, __) => Divider(color: cs.outlineVariant),
                        itemBuilder: (_, i) {
                          final row = recentOffers[i];

                          final id = row['id']?.toString() ?? '';
                          final production = (row['production'] ?? '—').toString();
                          final company = (row['company'] ?? '—').toString();
                          final contact = (row['contact'] ?? '').toString();
                          final status = (row['status'] ?? 'Draft').toString();
                          final updated = _fmtDateTime(row['updated_at'] ?? row['created_at']);

                          final isDraft = status.toLowerCase() == "draft";
                          final badgeBg = isDraft ? cs.tertiaryContainer : cs.secondaryContainer;
                          final badgeText = isDraft ? "Draft" : "Final";

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Text("${i + 1}"),
                            ),
                            title: Text(
                              production,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              contact.trim().isEmpty
                                  ? "$company • $updated"
                                  : "$company • $contact • $updated",
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),

                            /// ✅ KRITISK: bruk alltid /new/:id (path param)
                            onTap: id.isEmpty ? null : () => context.go("/new/$id"),
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