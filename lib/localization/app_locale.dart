import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supported languages for the Logistics portal.
const supportedLangs = ['en', 'no', 'sv', 'de', 'da'];

const _langNames = {
  'en': 'English',
  'no': 'Norsk',
  'sv': 'Svenska',
  'de': 'Deutsch',
  'da': 'Dansk',
};

String langName(String code) => _langNames[code] ?? code;

/// Global locale notifier — drives the entire app's language.
/// Persists to Supabase profiles table so it follows the user across devices.
final appLocale = AppLocale._();

class AppLocale extends ValueNotifier<Locale> {
  AppLocale._() : super(const Locale('en'));

  String get lang => value.languageCode;

  /// Load from Supabase profile. Falls back to English.
  Future<void> load() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;

      final res = await sb
          .from('profiles')
          .select('language')
          .eq('id', uid)
          .maybeSingle();

      final saved = res?['language'] as String?;
      if (saved != null && supportedLangs.contains(saved)) {
        value = Locale(saved);
      }
    } catch (e) {
      debugPrint('AppLocale.load error: $e');
    }
  }

  /// Save to Supabase profile and update in-memory locale.
  Future<void> setLang(String code) async {
    if (!supportedLangs.contains(code)) return;
    value = Locale(code);

    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;

      await sb.from('profiles').update({'language': code}).eq('id', uid);
    } catch (e) {
      debugPrint('AppLocale.setLang error: $e');
    }
  }
}
