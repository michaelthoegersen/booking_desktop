import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages muted chats. Muted chats don't send push notifications
/// unless the user is @mentioned.
class MuteService {
  static final _sb = Supabase.instance.client;
  static String get _uid => _sb.auth.currentUser!.id;

  /// Cached set of muted gig IDs.
  static Set<String> _mutedGigIds = {};
  static Set<String> _mutedGroupIds = {};
  static bool _loaded = false;

  /// Load muted chats from DB (call once on app start).
  static Future<void> load() async {
    try {
      final rows = await _sb
          .from('muted_chats')
          .select('gig_id, group_id')
          .eq('user_id', _uid);
      _mutedGigIds = {};
      _mutedGroupIds = {};
      for (final r in (rows as List)) {
        if (r['gig_id'] != null) _mutedGigIds.add(r['gig_id'] as String);
        if (r['group_id'] != null) _mutedGroupIds.add(r['group_id'] as String);
      }
      _loaded = true;
    } catch (_) {}
  }

  static bool isGigMuted(String gigId) => _mutedGigIds.contains(gigId);
  static bool isGroupMuted(String groupId) => _mutedGroupIds.contains(groupId);

  static Future<void> muteGig(String gigId) async {
    _mutedGigIds.add(gigId);
    await _sb.from('muted_chats').upsert({
      'user_id': _uid,
      'gig_id': gigId,
    }, onConflict: 'user_id,gig_id');
  }

  static Future<void> unmuteGig(String gigId) async {
    _mutedGigIds.remove(gigId);
    await _sb
        .from('muted_chats')
        .delete()
        .eq('user_id', _uid)
        .eq('gig_id', gigId);
  }

  static Future<void> muteGroup(String groupId) async {
    _mutedGroupIds.add(groupId);
    await _sb.from('muted_chats').upsert({
      'user_id': _uid,
      'group_id': groupId,
    }, onConflict: 'user_id,group_id');
  }

  static Future<void> unmuteGroup(String groupId) async {
    _mutedGroupIds.remove(groupId);
    await _sb
        .from('muted_chats')
        .delete()
        .eq('user_id', _uid)
        .eq('group_id', groupId);
  }

  static Future<void> toggleGig(String gigId) async {
    if (isGigMuted(gigId)) {
      await unmuteGig(gigId);
    } else {
      await muteGig(gigId);
    }
  }

  static Future<void> toggleGroup(String groupId) async {
    if (isGroupMuted(groupId)) {
      await unmuteGroup(groupId);
    } else {
      await muteGroup(groupId);
    }
  }
}
