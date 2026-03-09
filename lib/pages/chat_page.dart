import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../contacts/direct_chat_screen.dart';
import '../services/chat_service.dart';
import '../state/active_company.dart';
import '../ui/css_theme.dart';
import '../widgets/mention_helpers.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  _Thread? _selectedThread;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Venstre: tråd-liste
        SizedBox(
          width: 300,
          child: _ThreadList(
            selectedThread: _selectedThread,
            onSelect: (thread) {
              setState(() => _selectedThread = thread);
              // Merk som lest
              ChatService.markAsRead(
                dato: thread.dato,
                produksjon: thread.produksjon,
              );
            },
          ),
        ),

        const VerticalDivider(width: 1),

        // Høyre: aktiv tråd
        Expanded(
          child: _selectedThread == null
              ? const Center(
                  child: Text(
                    'Velg en tråd',
                    style: TextStyle(color: Colors.black45),
                  ),
                )
              : _ThreadView(
                  key: ValueKey(
                      '${_selectedThread!.dato}_${_selectedThread!.produksjon}'),
                  thread: _selectedThread!,
                  onDeleted: () => setState(() => _selectedThread = null),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tråd-modell (gruppert fra meldinger)
// ---------------------------------------------------------------------------

class _Thread {
  final String dato;
  final String produksjon;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;
  final String? userId; // første sjåfør-user_id i tråden

  const _Thread({
    required this.dato,
    required this.produksjon,
    required this.lastMessage,
    required this.lastAt,
    required this.unreadCount,
    this.userId,
  });
}

List<_Thread> _groupToThreads(List<Map<String, dynamic>> messages) {
  final Map<String, List<Map<String, dynamic>>> grouped = {};

  for (final msg in messages) {
    final key = '${msg['dato']}__${msg['produksjon']}';
    grouped.putIfAbsent(key, () => []).add(msg);
  }

  final threads = <_Thread>[];
  for (final entry in grouped.entries) {
    final msgs = entry.value;
    msgs.sort((a, b) => (a['created_at'] as String)
        .compareTo(b['created_at'] as String));

    final last = msgs.last;
    final unread = msgs
        .where((m) => m['is_admin'] == false && m['read_by_admin'] == false)
        .length;

    final driverMsg = msgs.firstWhere(
      (m) => m['is_admin'] == false,
      orElse: () => <String, dynamic>{},
    );

    threads.add(_Thread(
      dato: last['dato'] as String,
      produksjon: last['produksjon'] as String,
      lastMessage: last['message'] as String,
      lastAt: DateTime.tryParse(last['created_at'] as String? ?? '') ??
          DateTime.now(),
      unreadCount: unread,
      userId: driverMsg['user_id'] as String?,
    ));
  }

  threads.sort((a, b) => b.lastAt.compareTo(a.lastAt));
  return threads;
}

// ---------------------------------------------------------------------------
// Tråd-liste (venstre panel)
// ---------------------------------------------------------------------------

class _ThreadList extends StatelessWidget {
  final _Thread? selectedThread;
  final void Function(_Thread) onSelect;

  const _ThreadList({
    required this.selectedThread,
    required this.onSelect,
  });

  Future<void> _showNewDmPicker(BuildContext context) async {
    final sb = Supabase.instance.client;
    final myId = sb.auth.currentUser?.id ?? '';
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return;

    try {
      // Bruk SECURITY DEFINER-funksjon for å omgå RLS
      final res = await sb.rpc('get_company_member_profiles', params: {
        'p_company_id': companyId,
      });
      final contacts = List<Map<String, dynamic>>.from(res as List)
        ..removeWhere((c) => c['id'].toString() == myId);

      if (!context.mounted) return;

      final picked = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ny samtale'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: contacts.isEmpty
                ? const Center(
                    child: Text('Ingen kontakter',
                        style: TextStyle(color: CssTheme.textMuted)),
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (_, i) {
                      final c = contacts[i];
                      final name = c['name'] as String? ?? '';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.black,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(name),
                        onTap: () => Navigator.pop(ctx, c),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
          ],
        ),
      );

      if (picked != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              peerId: picked['id'].toString(),
              peerName: picked['name'] as String? ?? '',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('New DM picker error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CssTheme.outline)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Chat',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _showNewDmPicker(context),
                icon: const Icon(Icons.add),
                tooltip: 'Ny direktemelding',
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ChatService.streamAllMessages(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Feil: ${snapshot.error}'));
              }

              final threads = _groupToThreads(snapshot.data ?? []);

              if (threads.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Ingen meldinger ennå',
                      style: TextStyle(color: Colors.black45),
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: threads.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: CssTheme.outline),
                itemBuilder: (context, i) {
                  final thread = threads[i];
                  final isSelected = selectedThread?.dato == thread.dato &&
                      selectedThread?.produksjon == thread.produksjon;

                  return _ThreadTile(
                    thread: thread,
                    isSelected: isSelected,
                    onTap: () => onSelect(thread),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final _Thread thread;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThreadTile({
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtDate(thread.dato);
    final timeStr = DateFormat('HH:mm').format(thread.lastAt.toLocal());

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? Colors.black : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.produksjon.isEmpty ? '—' : thread.produksjon,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr • $timeStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white60 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    thread.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (thread.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  thread.unreadCount > 99
                      ? '99+'
                      : '${thread.unreadCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.red : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

// ---------------------------------------------------------------------------
// Aktiv tråd (høyre panel)
// ---------------------------------------------------------------------------

class _ThreadView extends StatefulWidget {
  final _Thread thread;
  final VoidCallback onDeleted;

  const _ThreadView({
    super.key,
    required this.thread,
    required this.onDeleted,
  });

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> with MentionMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _sending = false;
  String? _editingMessageId;
  Map<String, dynamic>? _replyTo;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _controller.addListener(() => onMentionTextChanged(_controller));
    _loadMentionCandidates();
  }

  Future<void> _loadMentionCandidates() async {
    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId == null) return;
      final rows = await Supabase.instance.client.rpc(
        'get_company_member_profiles',
        params: {'p_company_id': companyId},
      );
      final myId = Supabase.instance.client.auth.currentUser?.id;
      final candidates = (rows as List)
          .where((r) => r['id'] != myId)
          .map((r) => MentionCandidate(
                id: r['id'] as String,
                name: r['name'] as String? ?? '',
              ))
          .where((c) => c.name.isNotEmpty)
          .toList();
      if (mounted) initMentionCandidates(candidates);
    } catch (_) {}
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett tråd'),
        content: Text(
          'Er du sikker på at du vil slette hele samtalen for '
          '${widget.thread.produksjon} (${_fmtDate(widget.thread.dato)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ChatService.deleteThread(
        dato: widget.thread.dato,
        produksjon: widget.thread.produksjon,
      );
      widget.onDeleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette tråd: $e')),
        );
      }
    }
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

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      if (_editingMessageId != null) {
        await ChatService.updateMessage(_editingMessageId!, text);
        setState(() => _editingMessageId = null);
      } else {
        final mentions = List<String>.from(mentionedUserIds);
        await ChatService.sendAdminMessage(
          dato: widget.thread.dato,
          produksjon: widget.thread.produksjon,
          message: text,
          targetUserId: widget.thread.userId,
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

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtDate(widget.thread.dato);

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CssTheme.outline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.thread.produksjon.isEmpty
                          ? '—'
                          : widget.thread.produksjon,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _confirmDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Slett tråd',
                style: IconButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),

        // Meldingsliste
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ChatService.streamMessages(
              dato: widget.thread.dato,
              produksjon: widget.thread.produksjon,
            ),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];

              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    'Ingen meldinger',
                    style: TextStyle(color: Colors.black45),
                  ),
                );
              }

              final myId = Supabase.instance.client.auth.currentUser?.id ?? '';
              return ListView.separated(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(20),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final msg = messages[i];
                  final isAdmin = msg['is_admin'] == true;
                  final isMine = msg['user_id'] == myId;

                  Map<String, dynamic>? replyMsg;
                  final replyToId = msg['reply_to_id'];
                  if (replyToId != null) {
                    replyMsg = messages.cast<Map<String, dynamic>?>().firstWhere(
                      (m) => m?['id'] == replyToId,
                      orElse: () => null,
                    );
                  }

                  return _DesktopBubble(
                    message: msg['message'] as String,
                    senderName: msg['sender_name'] as String,
                    isAdmin: isAdmin,
                    createdAt: msg['created_at'] as String?,
                    editedAt: msg['edited_at'] as String?,
                    replyMsg: replyMsg,
                    onReply: () => _startReply(msg),
                    onEdit: isMine ? () => _startEdit(msg) : null,
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
            child: Row(
              children: [
                Container(
                  width: 3, height: 36,
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      Text(
                        _truncate(_replyTo!['message'] as String? ?? '', 60),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelReply),
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
                const Text('Redigerer melding', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelEdit),
              ],
            ),
          ),

        // Tekstfelt
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: CssTheme.outline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Svar som Michael…',
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
                        _editingMessageId != null ? Icons.check_rounded : Icons.send_rounded,
                        size: 18,
                      ),
                      label: Text(_editingMessageId != null ? 'Lagre' : 'Send'),
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
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _DesktopBubble extends StatelessWidget {
  final String message;
  final String senderName;
  final bool isAdmin;
  final String? createdAt;
  final String? editedAt;
  final Map<String, dynamic>? replyMsg;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;

  const _DesktopBubble({
    required this.message,
    required this.senderName,
    required this.isAdmin,
    this.createdAt,
    this.editedAt,
    this.replyMsg,
    this.onReply,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _fmtTime(createdAt);
    final maxWidth = MediaQuery.of(context).size.width * 0.55;

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isAdmin ? Colors.black : const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isAdmin ? 16 : 4),
                bottomRight: Radius.circular(isAdmin ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isAdmin ? Colors.white60 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 3),
                // Reply quote
                if (replyMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: isAdmin
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: isAdmin ? Colors.white54 : Colors.black26,
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
                            color: isAdmin ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        Text(
                          _truncate(replyMsg!['message'] as String? ?? '', 60),
                          style: TextStyle(
                            fontSize: 12,
                            color: isAdmin ? Colors.white54 : Colors.black45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
                Text.rich(
                  TextSpan(
                    children: buildMentionSpans(
                      message,
                      TextStyle(
                        fontSize: 14,
                        color: isAdmin ? Colors.white : Colors.black87,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: isAdmin ? Colors.white : Colors.black87,
                    ),
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
                          color: isAdmin ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      if (editedAt != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(redigert)',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isAdmin ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    if (onReply == null && onEdit == null) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy - 50,
        offset.dx + box.size.width, offset.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (onReply != null)
          PopupMenuItem<String>(
            value: 'reply',
            child: Row(children: const [Icon(Icons.reply, size: 18), SizedBox(width: 8), Text('Svar')]),
          ),
        if (onEdit != null)
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(children: const [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Rediger')]),
          ),
      ],
    ).then((value) {
      if (value == 'reply') onReply?.call();
      if (value == 'edit') onEdit?.call();
    });
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String? _fmtTime(String? iso) {
    if (iso == null) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return null;
    }
  }
}
