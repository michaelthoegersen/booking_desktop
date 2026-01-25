import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'widgets/app_shell.dart';

import 'pages/dashboard_page.dart';
import 'pages/new_offer_page.dart';
import 'pages/edit_offer_page.dart';
import 'pages/customers_page.dart';
import 'pages/settings_page.dart';
import 'pages/routes_admin_page.dart';

import 'state/settings_store.dart';
import 'ui/css_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseKey == null) {
      throw Exception("Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env");
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );

    await SettingsStore.load();
  } catch (e) {
    debugPrint("MAIN INIT ERROR: $e");
  }

  runApp(const BookingApp());
}

class BookingApp extends StatelessWidget {
  const BookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: "/",

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
        ShellRoute(
          builder: (context, state, child) {
            return AppShell(child: child);
          },
          routes: [
            // ---------------- DASHBOARD ----------------
            GoRoute(
              path: "/",
              builder: (context, state) => const DashboardPage(),
            ),

            // ---------------- NEW OFFER ----------------
            GoRoute(
              path: "/new",
              builder: (context, state) {
                final id = state.uri.queryParameters['id'];
                return NewOfferPage(offerId: id);
              },
            ),

            GoRoute(
              path: "/new/:id",
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NewOfferPage(offerId: id);
              },
            ),

            // ---------------- EDIT OFFER ----------------
            GoRoute(
              path: "/edit",
              builder: (context, state) => const EditOfferPage(),
            ),

            // ---------------- CUSTOMERS ----------------
            GoRoute(
              path: "/customers",
              builder: (context, state) => const CustomersPage(),
            ),

            // ---------------- SETTINGS ----------------
            GoRoute(
              path: "/settings",
              builder: (context, state) => const SettingsPage(),
            ),

            // ---------------- ROUTES ADMIN ----------------
            GoRoute(
              path: "/routes",
              builder: (context, state) => const RoutesAdminPage(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: "Booking System",
      theme: CssTheme.theme(),
      routerConfig: router,
    );
  }
}