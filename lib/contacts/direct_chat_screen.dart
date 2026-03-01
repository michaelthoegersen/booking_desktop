import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/direct_chat_service.dart';
import '../ui/css_theme.dart';

class DirectChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;

  const DirectChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String _senderName = '';

  /// Cached reactions: messageId → list of reaction maps
  Map<String, List<Map<String, dynamic>>> _reactionsByMessage = {};

  /// Current message IDs for streaming reactions
  List<String> _currentMessageIds = [];

  @override
  void initState() {
    super.initState();
    _loadSenderName();
  }

  Future<void> _loadSenderName() async {
    final name = await DirectChatService.getSenderName();
    if (mounted) setState(() => _senderName = name);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await DirectChatService.sendMessage(
        peerId: widget.peerId,
        message: text,
        senderName: _senderName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved sending: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _updateReactionsStream(List<String> messageIds) {
    if (_listEquals(messageIds, _currentMessageIds)) return;
    _currentMessageIds = messageIds;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: CssTheme.outline)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  backgroundColor: Colors.black,
                  radius: 18,
                  child: Text(
                    widget.peerName.isNotEmpty
                        ? widget.peerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DirectChatService.streamMessages(widget.peerId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                _scrollToBottom();

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Ingen meldinger ennå',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }

                // Collect message IDs for reactions stream
                final messageIds = messages
                    .map((m) => m['id']?.toString())
                    .whereType<String>()
                    .toList();
                _updateReactionsStream(messageIds);

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DirectChatService.streamReactions(messageIds),
                  builder: (context, reactSnap) {
                    // Build reaction map
                    final reactionsMap =
                        <String, List<Map<String, dynamic>>>{};
                    for (final r in reactSnap.data ?? []) {
                      final mid = r['message_id'] as String? ?? '';
                      reactionsMap.putIfAbsent(mid, () => []).add(r);
                    }
                    _reactionsByMessage = reactionsMap;

                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final msg = messages[i];
                        final msgId = msg['id']?.toString() ?? '';
                        final isMine = msg['sender_id'] == _currentUserId;
                        final reactions = _reactionsByMessage[msgId] ?? [];

                        return _Bubble(
                          messageId: msgId,
                          message: msg['message'] as String? ?? '',
                          senderName: msg['sender_name'] as String? ?? '',
                          isMine: isMine,
                          createdAt: msg['created_at'] as String?,
                          reactions: reactions,
                          currentUserId: _currentUserId,
                          onAddReaction: (emoji) =>
                              DirectChatService.addReaction(msgId, emoji),
                          onRemoveReaction: (emoji) =>
                              DirectChatService.removeReaction(msgId, emoji),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: CssTheme.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Skriv en melding…',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _sending
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Send'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _currentUserId {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  }
}

// ---------------------------------------------------------------------------
// Chat bubble with reactions
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  final String messageId;
  final String message;
  final String senderName;
  final bool isMine;
  final String? createdAt;
  final List<Map<String, dynamic>> reactions;
  final String currentUserId;
  final Future<void> Function(String emoji) onAddReaction;
  final Future<void> Function(String emoji) onRemoveReaction;

  const _Bubble({
    required this.messageId,
    required this.message,
    required this.senderName,
    required this.isMine,
    this.createdAt,
    required this.reactions,
    required this.currentUserId,
    required this.onAddReaction,
    required this.onRemoveReaction,
  });

  static const _emojiOptions = ['👍', '❤️', '😂', '😮', '🙏', '🔥'];

  @override
  Widget build(BuildContext context) {
    final timeStr = _fmtTime(createdAt);
    final maxWidth = MediaQuery.of(context).size.width * 0.55;

    // Group reactions: emoji → {count, myReaction}
    final Map<String, _ReactionInfo> grouped = {};
    for (final r in reactions) {
      final emoji = r['emoji'] as String? ?? '';
      final userId = r['user_id'] as String? ?? '';
      grouped.putIfAbsent(emoji, () => _ReactionInfo());
      grouped[emoji]!.count++;
      if (userId == currentUserId) grouped[emoji]!.isMine = true;
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Bubble
            GestureDetector(
              onLongPress: () => _showEmojiPicker(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMine ? Colors.black : const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMine ? 16 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isMine ? Colors.white60 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14,
                        color: isMine ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (timeStr != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: isMine ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Reaction pills
            if (grouped.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: grouped.entries.map((e) {
                    final emoji = e.key;
                    final info = e.value;
                    return GestureDetector(
                      onTap: () {
                        if (info.isMine) {
                          onRemoveReaction(emoji);
                        } else {
                          onAddReaction(emoji);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: info.isMine
                              ? Colors.blue.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: info.isMine
                                ? Colors.blue.withValues(alpha: 0.4)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          info.count > 1 ? '$emoji ${info.count}' : emoji,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEmojiPicker(BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - 50,
        offset.dx + box.size.width,
        offset.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _emojiOptions.map((emoji) {
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(context).pop();
                  onAddReaction(emoji);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String? _fmtTime(String? iso) {
    if (iso == null) return null;
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return null;
    }
  }
}

class _ReactionInfo {
  int count = 0;
  bool isMine = false;
}
