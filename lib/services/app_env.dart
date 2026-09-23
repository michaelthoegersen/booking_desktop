import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Single source for build-time configuration.
///
/// A value can arrive two ways:
///   1. `--dart-define=NAME=...` — release builds (web, DMG, IPA, APK)
///   2. the bundled `.env` asset — dev runs, and web too, since `.env` is
///      listed under `assets:` in pubspec.yaml
///
/// dart-define always wins. [ensureLoaded] must run once at startup before any
/// getter is read, so the `.env` fallback is actually available; it is safe to
/// call repeatedly and never throws.
///
/// This class exists because the two sources used to be mutually exclusive:
/// `main()` only called `dotenv.load()` when Supabase came from `.env`, so
/// passing `--dart-define` for Supabase left dotenv uninitialised and silently
/// killed every other key (Google Maps, Giphy). Read configuration through
/// here, never through `dotenv.env` directly.
class AppEnv {
  AppEnv._();

  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const String _giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');

  static bool _loadAttempted = false;

  /// Loads the bundled `.env` once. Missing or unreadable file is not an
  /// error — the dart-define values still apply.
  static Future<void> ensureLoaded() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('AppEnv: .env unavailable ($e) — using --dart-define only');
    }
  }

  /// Reads from the loaded `.env`. `dotenv.env` throws when the file was never
  /// loaded, so guard on [DotEnv.isInitialized] as well as catching.
  static String _fromFile(String name) {
    try {
      if (!dotenv.isInitialized) return '';
      return dotenv.env[name] ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _read(String defined, String name) =>
      defined.isNotEmpty ? defined : _fromFile(name);

  static String get supabaseUrl => _read(_supabaseUrl, 'SUPABASE_URL');
  static String get supabaseAnonKey =>
      _read(_supabaseAnonKey, 'SUPABASE_ANON_KEY');
  static String get googleMapsApiKey =>
      _read(_googleMapsApiKey, 'GOOGLE_MAPS_API_KEY');
  static String get giphyApiKey => _read(_giphyApiKey, 'GIPHY_API_KEY');
}
