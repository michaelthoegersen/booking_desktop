import 'app_locale.dart';
import 'strings/nav_strings.dart';
import 'strings/common_strings.dart';
import 'strings/topbar_strings.dart';
import 'strings/settings_strings.dart';
import 'strings/dashboard_strings.dart';
import 'strings/pages_strings.dart';
import 'strings/calendar_strings.dart';
import 'strings/offer_strings.dart';
import 'strings/chat_strings.dart';

/// Simple translation lookup.
///
/// Usage: `S.t('dashboard')` or with explicit lang: `S.t('dashboard', lang: 'no')`
class S {
  S._();

  /// All registered translation maps — order doesn't matter, keys must be unique.
  static final List<Map<String, Map<String, String>>> _maps = [
    navStrings,
    commonStrings,
    topbarStrings,
    settingsStrings,
    dashboardStrings,
    pagesStrings,
    calendarStrings,
    offerStrings,
    chatStrings,
  ];

  /// Look up [key] in the current locale (or override with [lang]).
  /// Falls back to English, then returns the key itself.
  static String t(String key, {String? lang}) {
    final l = lang ?? appLocale.lang;
    for (final map in _maps) {
      final entry = map[key];
      if (entry != null) {
        return entry[l] ?? entry['en'] ?? key;
      }
    }
    return key;
  }
}
