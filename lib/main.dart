import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/login_page.dart';
import 'widgets/app_shell.dart';
import 'widgets/mgmt_shell.dart';
import 'widgets/crew_shell.dart';

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
import 'pages/economy_page.dart';
import 'pages/chat_page.dart';
import 'pages/archive_page.dart';
import 'pages/bus_requests_page.dart';

import 'pages/mgmt/mgmt_dashboard_page.dart';
import 'pages/mgmt/mgmt_tours_page.dart';
import 'pages/mgmt/mgmt_tour_detail_page.dart';
import 'pages/mgmt/mgmt_gigs_page.dart';
import 'pages/mgmt/mgmt_gig_detail_page.dart';
import 'pages/mgmt/mgmt_people_page.dart';
import 'pages/mgmt/mgmt_messages_page.dart';
import 'pages/mgmt/mgmt_settings_page.dart';

import 'pages/crew/crew_gigs_page.dart';
import 'pages/crew/crew_gig_detail_page.dart';

import 'state/active_company.dart';
import 'state/settings_store.dart';
import 'ui/css_theme.dart';


// ------------------------------------------------------------
// MAIN
// ------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? supabaseUrl;
  String? supabaseKey;

  // 1. dart-define (Release / DMG)
  const envUrl = String.fromEnvironment('SUPABASE_URL');
  const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (envUrl.isNotEmpty && envKey.isNotEmpty) {
    supabaseUrl = envUrl;
    supabaseKey = envKey;
  } else {
    // 2. .env-fil (VSCode / flutter run desktop)
    try {
      await dotenv.load(fileName: ".env");
      supabaseUrl = dotenv.env['SUPABASE_URL'];
      supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
    } catch (e) {
      // Chrome dev-server blokkerer .env-filer — bruk inline fallback.
      // Anon-nøkkelen er offentlig (synlig i nettverksforespørsler).
      debugPrint("dotenv load failed ($e) — using inline fallback");
      supabaseUrl = 'https://fqefvgqlrntwgschkugf.supabase.co';
      supabaseKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxZWZ2Z3Fscm50d2dzY2hrdWdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwNzQxMjAsImV4cCI6MjA4NDY1MDEyMH0'
          '.ZamQr1qQRuYnQcy-yKfOr0IZrRJxIb4SP8_USn9uMoU';
    }
  }

  try {
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

// Cached user role to avoid repeated DB calls on every redirect
String? _cachedUserRole;

Future<void> _loadUserRole() async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) {
    _cachedUserRole = null;
    return;
  }
  try {
    final res = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();
    _cachedUserRole = res?['role'] as String?;
    await activeCompanyNotifier.load();
  } catch (e) {
    debugPrint('_loadUserRole error: $e');
    _cachedUserRole = null;
  }
}


// ------------------------------------------------------------
// SUPABASE AUTH REFRESHER
// ------------------------------------------------------------
class SupabaseAuthRefresher extends ChangeNotifier {
  SupabaseAuthRefresher() {
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      // Clear cached role on auth state change
      if (event.event == AuthChangeEvent.signedOut) {
        _cachedUserRole = null;
        activeCompanyNotifier.clear();
      }
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
      // AUTH REDIRECT (async for role-based routing)
      // --------------------------------------------------
      redirect: (context, state) async {
        final loggedIn = isLoggedIn;
        final path = state.matchedLocation;

        if (!loggedIn && path != '/login') return '/login';

        if (loggedIn && path == '/login') {
          await _loadUserRole();
          final mode = activeCompanyNotifier.value?.appMode ?? 'css';
          if (mode == 'management') return '/m';
          if (mode == 'crew') return '/c';
          return '/';
        }

        // If role not yet loaded but user is logged in, load it
        if (loggedIn && _cachedUserRole == null) {
          await _loadUserRole();
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

        // ---------------- CSS APP SHELL ----------------
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
                final qp = state.uri.queryParameters;
                final id = qp['id'];
                return NewOfferPage(
                  offerId: id,
                  prefillCompany: qp['company'],
                  prefillContact: qp['contact'],
                  prefillPhone: qp['phone'],
                  prefillEmail: qp['email'],
                  prefillProduction: qp['production'],
                  prefillFromCity: qp['fromCity'],
                  prefillToCity: qp['toCity'],
                  prefillDateFrom: qp['dateFrom'],
                  prefillDateTo: qp['dateTo'],
                  prefillStops: qp['stops'],
                  busRequestId: qp['busRequestId'],
                  prefillPax: int.tryParse(qp['pax'] ?? ''),
                  prefillBusCount: int.tryParse(qp['busCount'] ?? ''),
                  prefillTrailer: qp['trailer'] == 'true',
                );
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

            // ---------------- CHAT ----------------
            GoRoute(
              path: "/chat",
              builder: (context, state) => const ChatPage(),
            ),

            // ---------------- ECONOMY ----------------
            GoRoute(
              path: "/economy",
              builder: (context, state) => const EconomyPage(),
            ),

            // ---------------- ARCHIVE ----------------
            GoRoute(
              path: "/archive",
              builder: (context, state) => const ArchivePage(),
            ),

            // ---------------- BUS REQUESTS ----------------
            GoRoute(
              path: "/bus-requests",
              builder: (context, state) => const BusRequestsPage(),
            ),

            // ---------------- GOOGLE TEST ----------------
            GoRoute(
              path: "/google-test",
              builder: (context, state) => const GoogleTestPage(),
            ),
          ],
        ),

        // ---------------- MANAGEMENT SHELL ----------------
        ShellRoute(
          builder: (context, state, child) => MgmtShell(child: child),
          routes: [
            GoRoute(
              path: '/m',
              builder: (_, __) => const MgmtDashboardPage(),
            ),
            GoRoute(
              path: '/m/tours',
              builder: (_, __) => const MgmtToursPage(),
            ),
            GoRoute(
              path: '/m/tours/:id',
              builder: (_, s) => MgmtTourDetailPage(
                tourId: s.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: '/m/gigs',
              builder: (_, __) => const MgmtGigsPage(),
            ),
            GoRoute(
              path: '/m/gigs/:id',
              builder: (_, s) => MgmtGigDetailPage(
                gigId: s.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: '/m/people',
              builder: (_, __) => const MgmtPeoplePage(),
            ),
            GoRoute(
              path: '/m/messages',
              builder: (_, __) => const MgmtMessagesPage(),
            ),
            GoRoute(
              path: '/m/settings',
              builder: (_, __) => const MgmtSettingsPage(),
            ),
          ],
        ),

        // ---------------- CREW SHELL ----------------
        ShellRoute(
          builder: (context, state, child) => CrewShell(child: child),
          routes: [
            GoRoute(
              path: '/c',
              builder: (_, __) => const CrewGigsPage(),
            ),
            GoRoute(
              path: '/c/gigs/:id',
              builder: (_, s) => CrewGigDetailPage(
                gigId: s.pathParameters['id']!,
              ),
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
