import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/direct_chat_service.dart';
import '../ui/css_theme.dart';
import 'direct_chat_screen.dart';

class DmInboxScreen extends StatefulWidget {
  const DmInboxScreen({super.key});

  @override
  State<DmInboxScreen> createState() => _DmInboxScreenState();
}

class _DmInboxScreenState extends State<DmInboxScreen> {
  final _sb = Supabase.instance.client;
  String get _myId => _sb.auth.currentUser?.id ?? '';

  /// Cache: peerId → {name, avatar_url}
  final Map<String, Map<String, dynamic>> _profileCache = {};

  Future<Map<String, dynamic>> _getProfile(String peerId) async {
    if (_profileCache.containsKey(peerId)) return _profileCache[peerId]!;
    try {
      final res = await _sb
          .from('profiles')
          .select('id, name, avatar_url')
          .eq('id', peerId)
          .maybeSingle();
      final profile = res ?? {'id': peerId, 'name': 'Unknown', 'avatar_url': null};
      _profileCache[peerId] = profile;
      return profile;
    } catch (_) {
      final fallback = {'id': peerId, 'name': 'Unknown', 'avatar_url': null};
      _profileCache[peerId] = fallback;
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meldinger',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Direktemeldinger',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CssTheme.textMuted,
                ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DirectChatService.streamAllMyMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allMessages = snapshot.data ?? [];

                if (allMessages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Ingen samtaler ennå',
                      style: TextStyle(color: CssTheme.textMuted),
                    ),
                  );
                }

                // Group by peer
                final Map<String, List<Map<String, dynamic>>> grouped = {};
                for (final msg in allMessages) {
                  final senderId = msg['sender_id'] as String? ?? '';
                  final receiverId = msg['receiver_id'] as String? ?? '';
                  final peerId = senderId == _myId ? receiverId : senderId;
                  grouped.putIfAbsent(peerId, () => []).add(msg);
                }

                // Sort each group by created_at descending, take latest
                final conversations = grouped.entries.map((e) {
                  final msgs = e.value;
                  msgs.sort((a, b) {
                    final aTime = a['created_at'] as String? ?? '';
                    final bTime = b['created_at'] as String? ?? '';
                    return bTime.compareTo(aTime);
                  });
                  return MapEntry(e.key, msgs.first);
                }).toList();

                // Sort conversations by latest message
                conversations.sort((a, b) {
                  final aTime = a.value['created_at'] as String? ?? '';
                  final bTime = b.value['created_at'] as String? ?? '';
                  return bTime.compareTo(aTime);
                });

                return ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, i) {
                    final peerId = conversations[i].key;
                    final lastMsg = conversations[i].value;
                    return _ConversationTile(
                      peerId: peerId,
                      lastMessage: lastMsg,
                      myId: _myId,
                      getProfile: _getProfile,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

class _ConversationTile extends StatefulWidget {
  final String peerId;
  final Map<String, dynamic> lastMessage;
  final String myId;
  final Future<Map<String, dynamic>> Function(String) getProfile;

  const _ConversationTile({
    required this.peerId,
    required this.lastMessage,
    required this.myId,
    required this.getProfile,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await widget.getProfile(widget.peerId);
    if (mounted) setState(() => _profile = p);
  }

  @override
  Widget build(BuildContext context) {
    final peerName = _profile?['name'] as String? ?? '';
    final avatarUrl = _profile?['avatar_url'] as String?;
    final message = widget.lastMessage['message'] as String? ?? '';
    final isMine = widget.lastMessage['sender_id'] == widget.myId;
    final timeStr = _fmtTime(widget.lastMessage['created_at'] as String?);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              peerId: widget.peerId,
              peerName: peerName,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CssTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CssTheme.outline),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              backgroundColor: Colors.black,
              radius: 22,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName.isEmpty ? 'Loading…' : peerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isMine ? 'Du: $message' : message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CssTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Timestamp
            if (timeStr != null)
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: CssTheme.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _fmtTime(String? iso) {
    if (iso == null) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays == 0) {
        return DateFormat('HH:mm').format(dt);
      } else if (diff.inDays == 1) {
        return 'I går';
      } else if (diff.inDays < 7) {
        return DateFormat('EEEE').format(dt);
      } else {
        return DateFormat('dd.MM.yy').format(dt);
      }
    } catch (_) {
      return null;
    }
  }
}
