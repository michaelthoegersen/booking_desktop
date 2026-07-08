import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends a push notification + in-app bell notification to a driver.
///
/// The driver is identified by their display name (from the `profiles.name`
/// column). The Edge Function does the rest: inserts into `notifications` and
/// fires the FCM push.
class NotificationService {
  static final _sb = Supabase.instance.client;

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Send a notification to a driver identified by their display name.
  /// Sends to ALL profiles matching the name (handles duplicates gracefully).
  /// Pick a localized title/body pair. [titlesByLang] keys: 'no','en','sv'.
  /// If the driver's profile has a language, use it; otherwise default to 'no'.
  static Future<bool> sendToDriver({
    required String driverName,
    required String title,
    String body = '',
    String? draftId,
    Map<String, String>? titlesByLang,
    Map<String, String>? bodiesByLang,
  }) async {
    try {
      debugPrint('🔔 sendToDriver: name="$driverName" title="$title"');

      final rows = await _sb
          .from('profiles')
          .select('id, language')
          .eq('name', driverName);

      final profiles = (rows as List).cast<Map<String, dynamic>>();

      if (profiles.isEmpty) {
        debugPrint('🔔 sendToDriver: no profile found for "$driverName"');
        return false;
      }

      debugPrint('🔔 sendToDriver: found ${profiles.length} profile(s)');

      bool anySent = false;
      for (final p in profiles) {
        final userId = p['id'] as String;
        final lang = (p['language'] as String?) ?? 'no';
        final localTitle = titlesByLang?[lang] ?? titlesByLang?['en'] ?? title;
        final localBody = bodiesByLang?[lang] ?? bodiesByLang?['en'] ?? body;
        final ok = await sendToUserId(
            userId: userId, title: localTitle, body: localBody, draftId: draftId);
        if (ok) anySent = true;
      }
      return anySent;
    } catch (e) {
      debugPrint('🔔 sendToDriver ERROR: $e');
      return false;
    }
  }

  /// Send a notification directly with a known Supabase user UUID.
  static Future<bool> sendToUserId({
    required String userId,
    required String title,
    String body = '',
    String? draftId,
  }) async {
    try {
      debugPrint('🔔 sendToUserId: userId=$userId title="$title"');
      final response = await _sb.functions.invoke(
        'send-push',
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          if (draftId != null) 'draft_id': draftId,
        },
      );

      debugPrint(
          '🔔 sendToUserId: status=${response.status} data=${response.data}');

      if (response.status != null && response.status! >= 400) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('🔔 sendToUserId ERROR: $e');
      return false;
    }
  }
}
