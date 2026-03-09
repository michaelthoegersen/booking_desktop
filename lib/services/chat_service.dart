import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  static final _sb = Supabase.instance.client;

  // Notifiserer sidebar umiddelbart når meldinger merkes som lest
  static final readEventNotifier = ValueNotifier<int>(0);

  // Stream alle tråder (admin ser alt) — grupperes i UI
  static Stream<List<Map<String, dynamic>>> streamAllMessages() {
    return _sb
        .from('tour_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => List<Map<String, dynamic>>.from(rows));
  }

  // Stream meldinger for én tråd
  static Stream<List<Map<String, dynamic>>> streamMessages({
    required String dato,
    required String produksjon,
  }) {
    return _sb
        .from('tour_messages')
        .stream(primaryKey: ['id'])
        .eq('dato', dato)
        .order('created_at')
        .map((rows) => rows
            .where((r) => r['produksjon'] == produksjon)
            .toList());
  }

  // Update own tour message text.
  static Future<void> updateMessage(String messageId, String newText) async {
    await _sb.from('tour_messages').update({
      'message': newText,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  // Send admin-svar
  static Future<void> sendAdminMessage({
    required String dato,
    required String produksjon,
    required String message,
    String? targetUserId,
    String? replyToId,
    List<String>? mentionedUserIds,
  }) async {
    await _sb.from('tour_messages').insert({
      'dato': dato,
      'produksjon': produksjon,
      'user_id': _sb.auth.currentUser?.id,
      'sender_name': 'Michael',
      'message': message,
      'is_admin': true,
      'read_by_admin': true,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
        'mentioned_user_ids': mentionedUserIds,
    });

    // Push til sjåfør hvis vi har user_id
    if (targetUserId != null) {
      try {
        await _sb.functions.invoke('send-chat-push', body: {
          'title': 'Svar fra Michael',
          'body': message,
          'target': 'user',
          'user_id': targetUserId,
          'data': {'screen': 'chat'},
        });
      } catch (e) {
        // Push er ikke kritisk
      }
    }
  }

  // Merk alle meldinger i en tråd som lest av admin
  static Future<void> markAsRead({
    required String dato,
    required String produksjon,
  }) async {
    await _sb
        .from('tour_messages')
        .update({'read_by_admin': true})
        .eq('dato', dato)
        .eq('produksjon', produksjon)
        .eq('is_admin', false);
    // Varsle sidebar umiddelbart
    readEventNotifier.value++;
  }

  // Slett hele tråden
  static Future<void> deleteThread({
    required String dato,
    required String produksjon,
  }) async {
    await _sb
        .from('tour_messages')
        .delete()
        .eq('dato', dato)
        .eq('produksjon', produksjon);
    readEventNotifier.value++;
  }

  // Antall uleste (fra sjåfører)
  static Future<int> unreadCount() async {
    final res = await _sb
        .from('tour_messages')
        .select('id')
        .eq('read_by_admin', false)
        .eq('is_admin', false);
    return res.length;
  }

  // Stream av uleste-count for badge
  static Stream<int> unreadCountStream() {
    return _sb
        .from('tour_messages')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
            .where((r) =>
                r['is_admin'] == false && r['read_by_admin'] == false)
            .length);
  }
}
