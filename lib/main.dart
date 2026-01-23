import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';

import 'widgets/app_shell.dart';
import 'pages/dashboard_page.dart';
import 'pages/new_offer_page.dart';
import 'pages/edit_offer_page.dart';
import 'pages/customers_page.dart';
import 'pages/settings_page.dart';

import 'state/settings_store.dart';
import 'ui/css_theme.dart'; // ✅ NY

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
      routes: [
        ShellRoute(
          builder: (context, state, child) {
            return AppShell(child: child);
          },
          routes: [
            GoRoute(
              path: "/",
              builder: (context, state) => const DashboardPage(),
            ),

            /// ✅ /new -> blank offer
            /// ✅ /new?id=UUID -> draft (query param)
            GoRoute(
              path: "/new",
              builder: (context, state) {
                final id = state.uri.queryParameters['id'];
                return NewOfferPage(offerId: id);
              },
            ),

            /// ✅ /new/<uuid>  --> FIXER "no routes for location"
            GoRoute(
              path: "/new/:id",
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NewOfferPage(offerId: id);
              },
            ),

            GoRoute(
              path: "/edit",
              builder: (context, state) => const EditOfferPage(),
            ),
            GoRoute(
              path: "/customers",
              builder: (context, state) => const CustomersPage(),
            ),
            GoRoute(
              path: "/settings",
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: "Booking System",
      theme: CssTheme.theme(), // ✅ mobil-look theme
      routerConfig: router,
    );
  }
}