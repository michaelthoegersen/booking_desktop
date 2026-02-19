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
  ///
  /// Returns `true` if the Edge Function was called without error.
  /// The Edge Function itself logs FCM errors; this method won't throw on
  /// FCM failures—only on network/function invocation errors.
  static Future<bool> sendToDriver({
    required String driverName,
    required String title,
    String body = '',
    String? draftId,
  }) async {
    try {
      final userId = await _userIdByName(driverName);
      if (userId == null) {
        // Driver not found in profiles — nothing to send
        return false;
      }
      return await sendToUserId(
          userId: userId, title: title, body: body, draftId: draftId);
    } catch (e) {
      // Swallow errors so the caller never crashes
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
      final response = await _sb.functions.invoke(
        'send-push',
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          if (draftId != null) 'draft_id': draftId,
        },
      );

      // FunctionsResponse.status is the HTTP status code
      if (response.status != null && response.status! >= 400) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Look up the Supabase user id for a given profile display name.
  static Future<String?> _userIdByName(String name) async {
    final res = await _sb
        .from('profiles')
        .select('id')
        .eq('name', name)
        .maybeSingle();

    return res?['id'] as String?;
  }
}
