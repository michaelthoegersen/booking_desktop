import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart'; // for debugPrint

import 'app_shell.dart';
import 'pages/dashboard_page.dart';
import 'pages/new_offer_page.dart';
import 'pages/edit_offer_page.dart';
import 'pages/customers_page.dart';
import 'pages/settings_page.dart';

import 'state/settings_store.dart'; // ✅ load settings

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // ✅ Load env
    await dotenv.load(fileName: ".env");

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseKey == null) {
      throw Exception("Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env");
    }

    // ✅ Init Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );

    // ✅ Load settings from SharedPreferences (Dropbox path etc.)
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
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const AppShell(child: DashboardPage()),
        ),
        GoRoute(
          path: '/new',
          builder: (_, __) => const AppShell(child: NewOfferPage()),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, __) => const AppShell(child: EditOfferPage()),
        ),
        GoRoute(
          path: '/customers',
          builder: (_, __) => const AppShell(child: CustomersPage()),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const AppShell(child: SettingsPage()),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Booking System',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      routerConfig: router,
    );
  }
}