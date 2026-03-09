import 'package:supabase_flutter/supabase_flutter.dart';

class DirectChatService {
  static final _sb = Supabase.instance.client;

  /// Realtime stream of DMs between current user and [peerId].
  static Stream<List<Map<String, dynamic>>> streamMessages(String peerId) {
    final myId = _sb.auth.currentUser!.id;
    return _sb
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.where((r) {
              final s = r['sender_id'] as String;
              final rv = r['receiver_id'] as String;
              return (s == myId && rv == peerId) ||
                  (s == peerId && rv == myId);
            }).toList());
  }

  /// Realtime stream of ALL DMs where current user is sender or receiver.
  /// Used for the DM inbox screen.
  static Stream<List<Map<String, dynamic>>> streamAllMyMessages() {
    final myId = _sb.auth.currentUser!.id;
    return _sb
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.where((r) {
              final s = r['sender_id'] as String;
              final rv = r['receiver_id'] as String;
              return s == myId || rv == myId;
            }).toList());
  }

  /// Update own DM text.
  static Future<void> updateMessage(String messageId, String newText) async {
    await _sb.from('direct_messages').update({
      'message': newText,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId).eq('sender_id', _sb.auth.currentUser!.id);
  }

  /// Send a DM to [peerId].
  static Future<void> sendMessage({
    required String peerId,
    required String message,
    required String senderName,
    String? replyToId,
    List<String>? mentionedUserIds,
  }) async {
    await _sb.from('direct_messages').insert({
      'sender_id': _sb.auth.currentUser!.id,
      'receiver_id': peerId,
      'sender_name': senderName,
      'message': message,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
        'mentioned_user_ids': mentionedUserIds,
    });

    // Push notification to receiver
    try {
      await _sb.functions.invoke('notify-chat', body: {
        'type': 'direct',
        'receiver_id': peerId,
        'sender_id': _sb.auth.currentUser!.id,
        'sender_name': senderName,
        'message': message,
        if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
          'mentioned_user_ids': mentionedUserIds,
      });
    } catch (_) {}
  }

  /// Convert a DM conversation to a group chat.
  static Future<String> convertToGroup(
    String peerId,
    String groupName, [
    List<String> additionalMemberIds = const [],
  ]) async {
    final result = await _sb.rpc('convert_dm_to_group', params: {
      'p_peer_id': peerId,
      'p_group_name': groupName,
      'p_additional_member_ids': additionalMemberIds,
    });
    return result as String;
  }

  /// Get current user's display name from profiles.
  static Future<String> getSenderName() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return '';
    final res = await _sb
        .from('profiles')
        .select('name')
        .eq('id', uid)
        .maybeSingle();
    return res?['name'] as String? ?? '';
  }

  /// Delete all DMs between current user and [peerId]. Requires admin role.
  static Future<void> deleteConversation(String peerId) async {
    final myId = _sb.auth.currentUser!.id;
    await _sb
        .from('direct_messages')
        .delete()
        .or('and(sender_id.eq.$myId,receiver_id.eq.$peerId),and(sender_id.eq.$peerId,receiver_id.eq.$myId)');
  }

  // -------------------------------------------------------------------
  // Reactions
  // -------------------------------------------------------------------

  /// Add (upsert) a reaction emoji on a message.
  static Future<void> addReaction(String messageId, String emoji) async {
    await _sb.from('direct_message_reactions').upsert({
      'message_id': messageId,
      'user_id': _sb.auth.currentUser!.id,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id,emoji');
  }

  /// Remove own reaction emoji from a message.
  static Future<void> removeReaction(String messageId, String emoji) async {
    await _sb
        .from('direct_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _sb.auth.currentUser!.id)
        .eq('emoji', emoji);
  }

  /// Realtime stream of reactions for all visible messages.
  static Stream<List<Map<String, dynamic>>> streamReactions(
      List<String> messageIds) {
    if (messageIds.isEmpty) return Stream.value([]);
    return _sb
        .from('direct_message_reactions')
        .stream(primaryKey: ['id']).map((rows) => rows
            .where((r) => messageIds.contains(r['message_id'] as String?))
            .toList());
  }
}
