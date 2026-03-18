import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages muted chats. Muted chats don't send push notifications
/// unless the user is @mentioned.
class MuteService {
  static final _sb = Supabase.instance.client;
  static String get _uid => _sb.auth.currentUser!.id;

  static Set<String> _mutedGigIds = {};
  static Set<String> _mutedGroupIds = {};
  static Set<String> _mutedPeerIds = {};

  /// Load muted chats from DB (call once on app start).
  static Future<void> load() async {
    try {
      final rows = await _sb
          .from('muted_chats')
          .select('gig_id, group_id, peer_id')
          .eq('user_id', _uid);
      _mutedGigIds = {};
      _mutedGroupIds = {};
      _mutedPeerIds = {};
      for (final r in (rows as List)) {
        if (r['gig_id'] != null) _mutedGigIds.add(r['gig_id'] as String);
        if (r['group_id'] != null) _mutedGroupIds.add(r['group_id'] as String);
        if (r['peer_id'] != null) _mutedPeerIds.add(r['peer_id'] as String);
      }
    } catch (_) {}
  }

  static bool isGigMuted(String gigId) => _mutedGigIds.contains(gigId);
  static bool isGroupMuted(String groupId) => _mutedGroupIds.contains(groupId);
  static bool isPeerMuted(String peerId) => _mutedPeerIds.contains(peerId);

  static Future<void> toggleGig(String gigId) async {
    if (isGigMuted(gigId)) {
      _mutedGigIds.remove(gigId);
      await _sb.from('muted_chats').delete().eq('user_id', _uid).eq('gig_id', gigId);
    } else {
      _mutedGigIds.add(gigId);
      await _sb.from('muted_chats').insert({'user_id': _uid, 'gig_id': gigId});
    }
  }

  static Future<void> toggleGroup(String groupId) async {
    if (isGroupMuted(groupId)) {
      _mutedGroupIds.remove(groupId);
      await _sb.from('muted_chats').delete().eq('user_id', _uid).eq('group_id', groupId);
    } else {
      _mutedGroupIds.add(groupId);
      await _sb.from('muted_chats').insert({'user_id': _uid, 'group_id': groupId});
    }
  }

  static Future<void> togglePeer(String peerId) async {
    if (isPeerMuted(peerId)) {
      _mutedPeerIds.remove(peerId);
      await _sb.from('muted_chats').delete().eq('user_id', _uid).eq('peer_id', peerId);
    } else {
      _mutedPeerIds.add(peerId);
      await _sb.from('muted_chats').insert({'user_id': _uid, 'peer_id': peerId});
    }
  }
}
