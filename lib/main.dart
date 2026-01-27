import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/login_page.dart';
import 'pages/customers_admin_page.dart';
import 'widgets/app_shell.dart';

import 'pages/dashboard_page.dart';
import 'pages/new_offer_page.dart';
import 'pages/edit_offer_page.dart';
import 'pages/customers_page.dart';
import 'pages/settings_page.dart';
import 'pages/routes_admin_page.dart';
import 'pages/calendar_page.dart'; // ✅ CALENDAR

import 'state/settings_store.dart';
import 'ui/css_theme.dart';

// ------------------------------------------------------------
// MAIN
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// AUTH HELPERS
// ------------------------------------------------------------
final supabase = Supabase.instance.client;

bool get isLoggedIn => supabase.auth.currentSession != null;

// ------------------------------------------------------------
// SUPABASE AUTH REFRESHER
// ------------------------------------------------------------
class SupabaseAuthRefresher extends ChangeNotifier {
  SupabaseAuthRefresher() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
}

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------
class BookingApp extends StatelessWidget {
  const BookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      refreshListenable: SupabaseAuthRefresher(),

      initialLocation: "/",

      // --------------------------------------------------
      // AUTH REDIRECT
      // --------------------------------------------------
      redirect: (context, state) {
        final loggedIn = isLoggedIn;
        final goingToLogin = state.matchedLocation == "/login";

        // Ikke logget inn → login
        if (!loggedIn && !goingToLogin) {
          return "/login";
        }

        // Logget inn → ikke login
        if (loggedIn && goingToLogin) {
          return "/";
        }

        return null;
      },

      // --------------------------------------------------
      // ERROR PAGE
      // --------------------------------------------------
      errorBuilder: (context, state) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Page not found",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
        // ---------------- LOGIN ----------------
        GoRoute(
          path: "/login",
          builder: (context, state) => const LoginPage(),
        ),

        // ---------------- APP SHELL ----------------
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

            // ---------------- CALENDAR ---------------- ✅
            GoRoute(
              path: "/calendar",
              builder: (context, state) => const CalendarPage(),
            ),

            // ---------------- CUSTOMERS ----------------
            GoRoute(
              path: "/customers",
              builder: (context, state) =>
                  const CustomersAdminPage(),
            ),

            // ---------------- SETTINGS ----------------
            GoRoute(
              path: "/settings",
              builder: (context, state) => const SettingsPage(),
            ),

            // ---------------- ROUTES ADMIN ----------------
            GoRoute(
              path: "/routes",
              builder: (context, state) =>
                  const RoutesAdminPage(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: "TourFlow",
      theme: CssTheme.theme(),
      routerConfig: router,
    );
  }
}