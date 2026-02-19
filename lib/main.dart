import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/login_page.dart';
import 'widgets/app_shell.dart';

import 'pages/dashboard_page.dart';
import 'pages/new_offer_page.dart';
import 'pages/edit_offer_page.dart';
import 'pages/customers_page.dart';
import 'pages/settings_page.dart';
import 'pages/routes_admin_page.dart';
import 'pages/calendar_page.dart';
import 'pages/google_test_page.dart';
import 'pages/invoices_page.dart';
import 'pages/issues_page.dart';

import 'state/settings_store.dart';
import 'ui/css_theme.dart';


// ------------------------------------------------------------
// MAIN
// ------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? supabaseUrl;
  String? supabaseKey;

  try {
    // 👉 Prøv først dart-define (Release / DMG)
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (envUrl.isNotEmpty && envKey.isNotEmpty) {
      supabaseUrl = envUrl;
      supabaseKey = envKey;
    } else {
      // 👉 Fallback til .env (VSCode / flutter run)
      await dotenv.load(fileName: ".env");

      supabaseUrl = dotenv.env['SUPABASE_URL'];
      supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
    }

    if (supabaseUrl == null ||
        supabaseKey == null ||
        supabaseUrl.isEmpty ||
        supabaseKey.isEmpty) {
      throw Exception("Missing Supabase config");
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );

    await SettingsStore.load();
    await SettingsStore.loadFerries();

    debugPrint("Supabase initialized OK");
  } catch (e, st) {
    debugPrint("MAIN INIT ERROR: $e");
    debugPrint("$st");
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

        if (!loggedIn && !goingToLogin) {
          return "/login";
        }

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

            // ---------------- CALENDAR ----------------
            GoRoute(
              path: "/calendar",
              builder: (context, state) => const CalendarPage(),
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

            // ---------------- ROUTES ----------------
            GoRoute(
              path: "/routes",
              builder: (context, state) => const RoutesAdminPage(),
            ),

            // ---------------- INVOICES ----------------
            GoRoute(
              path: "/invoices",
              builder: (context, state) => const InvoicesPage(),
            ),

            // ---------------- ISSUES ----------------
            GoRoute(
              path: "/issues",
              builder: (context, state) => const IssuesPage(),
            ),

            // ---------------- GOOGLE TEST ----------------
            GoRoute(
              path: "/google-test",
              builder: (context, state) => const GoogleTestPage(),
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