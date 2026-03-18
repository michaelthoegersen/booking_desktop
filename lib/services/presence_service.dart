import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks which users are online using Supabase Realtime Presence.
class PresenceService {
  static final _sb = Supabase.instance.client;
  static RealtimeChannel? _channel;

  /// Set of currently online user IDs.
  static final onlineUsers = ValueNotifier<Set<String>>({});

  /// Join the presence channel and start tracking.
  static void start() {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;

    _channel = _sb.channel('online-users');

    _channel!
        .onPresenceSync((payload) {
          final ids = <String>{};
          for (final state in _channel!.presenceState()) {
            for (final p in state.presences) {
              final uid = p.payload['user_id'] as String?;
              if (uid != null) ids.add(uid);
            }
          }
          onlineUsers.value = ids;
        })
        .onPresenceJoin((payload) {
          final newIds = Set<String>.from(onlineUsers.value);
          for (final p in payload.newPresences) {
            final uid = p.payload['user_id'] as String?;
            if (uid != null) newIds.add(uid);
          }
          onlineUsers.value = newIds;
        })
        .onPresenceLeave((payload) {
          final newIds = Set<String>.from(onlineUsers.value);
          for (final p in payload.leftPresences) {
            final uid = p.payload['user_id'] as String?;
            if (uid != null) newIds.remove(uid);
          }
          onlineUsers.value = newIds;
        })
        .subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({'user_id': myId});
          }
        });
  }

  /// Check if a user is online.
  static bool isOnline(String userId) => onlineUsers.value.contains(userId);

  /// Stop tracking.
  static void stop() {
    _channel?.unsubscribe();
    _channel = null;
    onlineUsers.value = {};
  }
}
