import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_attachment_service.dart';
import '../services/direct_chat_service.dart';
import '../services/poll_service.dart';
import '../state/active_company.dart';
import '../ui/css_theme.dart';
import '../widgets/chat_attach_menu.dart';
import '../widgets/chat_media_content.dart';
import '../widgets/gif_picker.dart';
import '../widgets/mention_helpers.dart';
import '../widgets/poll_create_dialog.dart';

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

class _DirectChatScreenState extends State<DirectChatScreen>
    with MentionMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _sending = false;
  String _senderName = '';

  /// Edit state
  String? _editingMessageId;

  /// Reply state
  Map<String, dynamic>? _replyTo;

  /// Cached reactions: messageId → list of reaction maps
  Map<String, List<Map<String, dynamic>>> _reactionsByMessage = {};

  /// Current message IDs for streaming reactions
  List<String> _currentMessageIds = [];

  /// Peer's read cursor for showing read receipts
  DateTime? _peerLastReadAt;

  @override
  void initState() {
    super.initState();
    _loadSenderName();
    _loadPeerReadCursor();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _controller.addListener(() => onMentionTextChanged(_controller));
    // In a DM, the only mention candidate is the peer
    initMentionCandidates([
      MentionCandidate(id: widget.peerId, name: widget.peerName),
    ]);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadSenderName() async {
    final name = await DirectChatService.getSenderName();
    if (mounted) setState(() => _senderName = name);
  }

  Future<void> _loadPeerReadCursor() async {
    try {
      final sb = Supabase.instance.client;
      final myId = sb.auth.currentUser?.id;
      if (myId == null) return;
      final row = await sb
          .from('dm_read_cursors')
          .select('last_read_at')
          .eq('user_id', widget.peerId)
          .eq('peer_id', myId)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _peerLastReadAt = DateTime.parse(row['last_read_at'] as String);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      if (_editingMessageId != null) {
        await DirectChatService.updateMessage(_editingMessageId!, text);
        setState(() => _editingMessageId = null);
      } else {
        final mentions = List<String>.from(mentionedUserIds);
        await DirectChatService.sendMessage(
          peerId: widget.peerId,
          message: text,
          senderName: _senderName,
          replyToId: _replyTo?['id'] as String?,
          mentionedUserIds: mentions.isNotEmpty ? mentions : null,
        );
        clearMentions();
        setState(() => _replyTo = null);
      }
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

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _sending = true);
    try {
      final url = await ChatAttachmentService.uploadFile(
        bytes: bytes,
        fileName: file.name,
        contentType: 'image/${file.extension ?? 'png'}',
      );
      await DirectChatService.sendMessage(
        peerId: widget.peerId,
        message: '',
        senderName: _senderName,
        messageType: 'image',
        attachmentUrl: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved opplasting: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _sending = true);
    try {
      final url = await ChatAttachmentService.uploadFile(
        bytes: bytes,
        fileName: file.name,
      );
      await DirectChatService.sendMessage(
        peerId: widget.peerId,
        message: file.name,
        senderName: _senderName,
        messageType: 'file',
        attachmentUrl: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved opplasting: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showGifPicker() {
    showDialog(
      context: context,
      builder: (_) => GifPicker(
        onGifSelected: (url) async {
          await DirectChatService.sendMessage(
            peerId: widget.peerId,
            message: '',
            senderName: _senderName,
            messageType: 'gif',
            attachmentUrl: url,
          );
        },
      ),
    );
  }

  void _showPollCreator() {
    showDialog(
      context: context,
      builder: (_) => PollCreateDialog(
        onCreate: (question, options) async {
          final pollId = await PollService.createPoll(
            question: question,
            options: options,
          );
          await DirectChatService.sendMessage(
            peerId: widget.peerId,
            message: question,
            senderName: _senderName,
            messageType: 'poll',
            attachmentUrl: pollId,
          );
        },
      ),
    );
  }

  void _startEdit(Map<String, dynamic> msg) {
    setState(() {
      _editingMessageId = msg['id'] as String;
      _replyTo = null;
      _controller.text = msg['message'] as String? ?? '';
    });
    _focusNode.requestFocus();
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() {
      _replyTo = msg;
      _editingMessageId = null;
      _controller.clear();
    });
    _focusNode.requestFocus();
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
                Expanded(
                  child: Text(
                    widget.peerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  tooltip: 'Legg til personer',
                  onPressed: () => _showConvertToGroupDialog(context),
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

                    // Find last message sent by me that peer has read
                    String? lastReadMsgId;
                    if (_peerLastReadAt != null) {
                      for (final m in messages) {
                        if (m['sender_id'] == _currentUserId) {
                          final ca = m['created_at'] as String?;
                          if (ca != null) {
                            final dt = DateTime.parse(ca);
                            if (!dt.isAfter(_peerLastReadAt!)) {
                              lastReadMsgId = m['id'] as String?;
                              break;
                            }
                          }
                        }
                      }
                    }

                    return ListView.separated(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(20),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final msg = messages[i];
                        final msgId = msg['id']?.toString() ?? '';
                        final isMine = msg['sender_id'] == _currentUserId;
                        final reactions = _reactionsByMessage[msgId] ?? [];

                        // Find reply-to message
                        Map<String, dynamic>? replyMsg;
                        final replyToId = msg['reply_to_id'];
                        if (replyToId != null) {
                          replyMsg = messages.cast<Map<String, dynamic>?>().firstWhere(
                            (m) => m?['id'] == replyToId,
                            orElse: () => null,
                          );
                        }

                        return _Bubble(
                          messageId: msgId,
                          message: msg['message'] as String? ?? '',
                          senderName: msg['sender_name'] as String? ?? '',
                          isMine: isMine,
                          createdAt: msg['created_at'] as String?,
                          editedAt: msg['edited_at'] as String?,
                          replyMsg: replyMsg,
                          reactions: reactions,
                          currentUserId: _currentUserId,
                          onAddReaction: (emoji) =>
                              DirectChatService.addReaction(msgId, emoji),
                          onRemoveReaction: (emoji) =>
                              DirectChatService.removeReaction(msgId, emoji),
                          onReply: () => _startReply(msg),
                          onEdit: isMine ? () => _startEdit(msg) : null,
                          messageType: msg['message_type'] as String? ?? 'text',
                          attachmentUrl: msg['attachment_url'] as String?,
                          showRead: isMine && msgId == lastReadMsgId,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Mention suggestions
          MentionOverlay(
            suggestions: mentionSuggestions,
            onSelect: (c) => insertMention(_controller, c),
          ),

          // Reply preview bar
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _replyTo!['sender_name'] as String? ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _truncate(_replyTo!['message'] as String? ?? '', 60),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelReply,
                  ),
                ],
              ),
            ),

          // Edit indicator bar
          if (_editingMessageId != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              color: const Color(0xFFFFF9C4),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  const Text(
                    'Redigerer melding',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelEdit,
                  ),
                ],
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
                ChatAttachMenu(
                  onPickImage: _pickImage,
                  onPickFile: _pickFile,
                  onGif: _showGifPicker,
                  onPoll: _showPollCreator,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
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
                        icon: Icon(
                          _editingMessageId != null
                              ? Icons.check_rounded
                              : Icons.send_rounded,
                          size: 18,
                        ),
                        label: Text(
                            _editingMessageId != null ? 'Lagre' : 'Send'),
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

  Future<void> _showConvertToGroupDialog(BuildContext context) async {
    final groupNameController = TextEditingController(text: widget.peerName);
    final selectedIds = <String>{};
    List<Map<String, dynamic>> contacts = [];

    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId != null) {
        final rows = await Supabase.instance.client.rpc(
          'get_company_member_profiles',
          params: {'p_company_id': companyId},
        );
        final myId = Supabase.instance.client.auth.currentUser?.id;
        contacts = (rows as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['id'] != myId && r['id'] != widget.peerId)
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Opprett gruppe'),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Gruppenavn',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (contacts.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Legg til personer:',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: contacts.length,
                          itemBuilder: (_, i) {
                            final c = contacts[i];
                            final id = c['id'] as String;
                            final name = c['name'] as String? ?? '';
                            return CheckboxListTile(
                              value: selectedIds.contains(id),
                              title: Text(name),
                              dense: true,
                              onChanged: (v) {
                                setDialogState(() {
                                  if (v == true) {
                                    selectedIds.add(id);
                                  } else {
                                    selectedIds.remove(id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.black),
                  child: const Text('Opprett'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;

    final name = groupNameController.text.trim();
    if (name.isEmpty) return;

    try {
      await DirectChatService.convertToGroup(
        widget.peerId,
        name,
        selectedIds.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppe opprettet!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  String get _currentUserId {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

// ---------------------------------------------------------------------------
// Chat bubble with reactions, reply quote, and edit label
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  final String messageId;
  final String message;
  final String senderName;
  final bool isMine;
  final String? createdAt;
  final String? editedAt;
  final Map<String, dynamic>? replyMsg;
  final List<Map<String, dynamic>> reactions;
  final String currentUserId;
  final Future<void> Function(String emoji) onAddReaction;
  final Future<void> Function(String emoji) onRemoveReaction;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final String messageType;
  final String? attachmentUrl;
  final bool showRead;

  const _Bubble({
    required this.messageId,
    required this.message,
    required this.senderName,
    required this.isMine,
    this.createdAt,
    this.editedAt,
    this.replyMsg,
    required this.reactions,
    required this.currentUserId,
    required this.onAddReaction,
    required this.onRemoveReaction,
    required this.onReply,
    this.onEdit,
    this.messageType = 'text',
    this.attachmentUrl,
    this.showRead = false,
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
              onSecondaryTapUp: (details) => _showContextMenu(context),
              onLongPress: () => _showContextMenu(context),
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
                    // Reply quote
                    if (replyMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isMine ? Colors.white54 : Colors.black26,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              replyMsg!['sender_name'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMine ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            Text(
                              _truncate(
                                  replyMsg!['message'] as String? ?? '', 60),
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine ? Colors.white54 : Colors.black45,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                    ChatMediaContent(
                      messageType: messageType,
                      message: message,
                      attachmentUrl: attachmentUrl,
                      isMine: isMine,
                      textStyle: TextStyle(
                        fontSize: 14,
                        color: isMine ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (timeStr != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: isMine ? Colors.white38 : Colors.black38,
                            ),
                          ),
                          if (editedAt != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(redigert)',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color:
                                    isMine ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                          if (showRead && isMine) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.done_all, size: 14,
                              color: Colors.blue.shade300),
                          ],
                        ],
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

  void _showContextMenu(BuildContext context) {
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
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Kopier'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'reply',
          child: Row(
            children: [
              Icon(Icons.reply, size: 18),
              SizedBox(width: 8),
              Text('Svar'),
            ],
          ),
        ),
        if (onEdit != null)
          const PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 8),
                Text('Rediger'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: message));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
        );
      } else if (value == 'reply') {
        onReply();
      } else if (value == 'edit' && onEdit != null) {
        onEdit!();
      }
    });
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

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
