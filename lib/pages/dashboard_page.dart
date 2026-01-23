import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/action_tile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int? routesCount;
  bool loadingRoutes = false;
  String? routesError;

  @override
  void initState() {
    super.initState();
    _loadRoutesCount();
  }

  Future<void> _loadRoutesCount() async {
    setState(() {
      loadingRoutes = true;
      routesError = null;
    });

    try {
      final client = Supabase.instance.client;

      // ✅ TABELLNAVN: routes_all (ikke routes_all / routes / noe annet tull)
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
      setState(() {
        loadingRoutes = false;
      });
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
          Text("Choose what you want to do.",
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),

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

          // ✅ SUPABASE STATUS CARD
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
                      Text("Routes in database",
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      if (loadingRoutes)
                        Text("Loading…",
                            style: TextStyle(color: cs.onSurfaceVariant))
                      else if (routesError != null)
                        Text("Error: $routesError",
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w700,
                            ))
                      else
                        Text(
                          routesCount == null
                              ? "—"
                              : "$routesCount route(s) found in routes_all",
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700),
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

          // ✅ ORIGINAL: Recent offers-listen din
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
                  Text("Recent offers",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: 8,
                      separatorBuilder: (_, __) =>
                          Divider(color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final status = i % 3 == 0 ? "Draft" : "Final";
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Text("${i + 1}")),
                          title: Text("Km Example Artist 202601${i + 10}"),
                          subtitle: const Text("Company name • Nightliner"),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: status == "Draft"
                                  ? cs.tertiaryContainer
                                  : cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(status,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ),
                          onTap: () => context.go("/edit"),
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