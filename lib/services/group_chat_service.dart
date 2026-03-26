import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupChatService {
  static final _sb = Supabase.instance.client;

  /// Opprett ny gruppe + legg til creator og valgte medlemmer.
  static Future<String> createGroup(
    String name,
    List<String> memberIds, {
    String? companyId,
  }) async {
    final myId = _sb.auth.currentUser!.id;

    final res = await _sb.from('group_chats').insert({
      'name': name,
      'created_by': myId,
      if (companyId != null) 'company_id': companyId,
    }).select('id').single();

    final groupId = res['id'] as String;

    // Legg til creator + alle valgte medlemmer
    final allMembers = {myId, ...memberIds};
    await _sb.from('group_chat_members').insert(
      allMembers.map((uid) => {
        'group_chat_id': groupId,
        'user_id': uid,
      }).toList(),
    );

    return groupId;
  }

  /// Realtime stream av grupper der bruker er medlem.
  /// RLS-policyen filtrerer automatisk til brukerens grupper.
  static Stream<List<Map<String, dynamic>>> streamMyGroups() {
    return _sb
        .from('group_chats')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  /// Realtime meldinger for en gruppe.
  static Stream<List<Map<String, dynamic>>> streamGroupMessages(
      String groupId) {
    return _sb
        .from('group_chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows
            .where((r) => r['group_chat_id'] == groupId)
            .toList());
  }

  /// Update own group message text.
  static Future<void> updateGroupMessage(String messageId, String newText) async {
    await _sb.from('group_chat_messages').update({
      'message': newText,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId).eq('user_id', _sb.auth.currentUser!.id);
  }

  /// Send melding til gruppe.
  static Future<void> sendGroupMessage({
    required String groupId,
    required String message,
    required String senderName,
    String? replyToId,
    List<String>? mentionedUserIds,
    String messageType = 'text',
    String? attachmentUrl,
  }) async {
    await _sb.from('group_chat_messages').insert({
      'group_chat_id': groupId,
      'user_id': _sb.auth.currentUser!.id,
      'sender_name': senderName,
      'message': message,
      'message_type': messageType,
      if (attachmentUrl != null) 'attachment_url': attachmentUrl,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
        'mentioned_user_ids': mentionedUserIds,
    });

    // Push notification to group members
    try {
      await _sb.functions.invoke('notify-chat', body: {
        'type': 'group',
        'group_id': groupId,
        'sender_id': _sb.auth.currentUser!.id,
        'sender_name': senderName,
        'message': message,
        if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
          'mentioned_user_ids': mentionedUserIds,
      });
    } catch (_) {}
  }

  /// Hent medlemmer med profiler.
  static Future<List<Map<String, dynamic>>> getGroupMembers(
      String groupId) async {
    final rows = await _sb
        .from('group_chat_members')
        .select('user_id, profiles(name, avatar_url)')
        .eq('group_chat_id', groupId);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Hent siste melding per gruppe (for inbox).
  static Future<Map<String, dynamic>?> getLastMessage(String groupId) async {
    final res = await _sb
        .from('group_chat_messages')
        .select()
        .eq('group_chat_id', groupId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res;
  }

  /// Oppdater avatar_url i group_chats.
  static Future<void> updateGroupAvatar(
      String groupId, String? avatarUrl) async {
    await _sb
        .from('group_chats')
        .update({'avatar_url': avatarUrl}).eq('id', groupId);
  }

  /// Last opp gruppebilde til group-avatars bucket, returner public URL.
  static Future<String?> uploadGroupAvatar(
      String groupId, File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final ext = imageFile.path.split('.').last.toLowerCase();
      final path = '$groupId/avatar.$ext';

      await _sb.storage.from('group-avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
          );

      final url = _sb.storage.from('group-avatars').getPublicUrl(path);

      await updateGroupAvatar(groupId, url);
      return url;
    } catch (e) {
      debugPrint('Group avatar upload error: $e');
      return null;
    }
  }

  /// Slett en gruppe. Cascade tar meldinger + medlemmer. Requires admin role.
  static Future<void> deleteGroup(String groupId) async {
    await _sb.from('group_chats').delete().eq('id', groupId);
  }

  /// Legg til nye medlemmer i gruppen.
  static Future<void> addMembers(
      String groupId, List<String> userIds) async {
    if (userIds.isEmpty) return;
    await _sb.from('group_chat_members').insert(
      userIds.map((uid) => {
            'group_chat_id': groupId,
            'user_id': uid,
          }).toList(),
    );
  }

  // -------------------------------------------------------------------
  // Reactions
  // -------------------------------------------------------------------

  /// Set reaction (one emoji per user — replaces previous).
  static Future<void> addReaction(String messageId, String emoji) async {
    final uid = _sb.auth.currentUser!.id;
    await _sb.from('group_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', uid);
    await _sb.from('group_message_reactions').insert({
      'message_id': messageId,
      'user_id': uid,
      'emoji': emoji,
    });
  }

  static Future<void> removeReaction(String messageId, String emoji) async {
    await _sb
        .from('group_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _sb.auth.currentUser!.id)
        .eq('emoji', emoji);
  }

  static Stream<List<Map<String, dynamic>>> streamReactions(
      List<String> messageIds) {
    if (messageIds.isEmpty) return Stream.value([]);
    return _sb
        .from('group_message_reactions')
        .stream(primaryKey: ['id']).map((rows) => rows
            .where((r) => messageIds.contains(r['message_id'] as String?))
            .toList());
  }

  /// Fjern et medlem fra gruppen.
  static Future<void> removeMember(String groupId, String userId) async {
    await _sb
        .from('group_chat_members')
        .delete()
        .eq('group_chat_id', groupId)
        .eq('user_id', userId);
  }
}
