import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/dashboard_page.dart';
import '../pages/new_offer_page.dart';
import '../pages/edit_offer_page.dart';
import '../pages/customers_page.dart';
import '../pages/settings_page.dart';
import '../pages/routes_admin_page.dart';

import '../widgets/app_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: "/",

  // --------------------------------------------------
  // ERROR HANDLER
  // --------------------------------------------------
  errorBuilder: (context, state) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Page not found",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(state.error?.toString() ?? ""),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go("/"),
              child: const Text("Go to dashboard"),
            ),
          ],
        ),
      ),
    );
  },

  routes: [
    // 🔴 ROOT ROUTE (VIKTIG)
    GoRoute(
      path: "/",
      builder: (context, state) => const SizedBox.shrink(),
      routes: [
        // --------------------------------------------------
        // SHELL
        // --------------------------------------------------
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            // DASHBOARD
            GoRoute(
              path: "",
              builder: (context, state) => const DashboardPage(),
            ),

            // NEW OFFER
            GoRoute(
              path: "new",
              builder: (context, state) {
                final id = state.uri.queryParameters['id'];
                return NewOfferPage(offerId: id);
              },
            ),

            GoRoute(
              path: "new/:id",
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NewOfferPage(offerId: id);
              },
            ),

            // EDIT OFFER
            GoRoute(
              path: "edit",
              builder: (context, state) => const EditOfferPage(),
            ),

            // CUSTOMERS
            GoRoute(
              path: "customers",
              builder: (context, state) => const CustomersPage(),
            ),

            // SETTINGS
            GoRoute(
              path: "settings",
              builder: (context, state) => const SettingsPage(),
            ),

            // ✅ ROUTES ADMIN — DEN FUNGERER NÅ
            GoRoute(
              path: "routes",
              builder: (context, state) => const RoutesAdminPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);