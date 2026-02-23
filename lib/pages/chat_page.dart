import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/chat_service.dart';
import '../ui/css_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CssTheme.outline)),
          ),
          child: const Text(
            'Chat',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
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

class _ThreadViewState extends State<_ThreadView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await ChatService.sendAdminMessage(
        dato: widget.thread.dato,
        produksjon: widget.thread.produksjon,
        message: text,
        targetUserId: widget.thread.userId,
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
              _scrollToBottom();

              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    'Ingen meldinger',
                    style: TextStyle(color: Colors.black45),
                  ),
                );
              }

              return ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final msg = messages[i];
                  final isAdmin = msg['is_admin'] == true;
                  return _DesktopBubble(
                    message: msg['message'] as String,
                    senderName: msg['sender_name'] as String,
                    isAdmin: isAdmin,
                    createdAt: msg['created_at'] as String?,
                  );
                },
              );
            },
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
                  onSubmitted: (_) => _send(),
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

class _DesktopBubble extends StatelessWidget {
  final String message;
  final String senderName;
  final bool isAdmin;
  final String? createdAt;

  const _DesktopBubble({
    required this.message,
    required this.senderName,
    required this.isAdmin,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _fmtTime(createdAt);
    final maxWidth = MediaQuery.of(context).size.width * 0.55;

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: isAdmin ? Colors.white : Colors.black87,
                ),
              ),
              if (timeStr != null) ...[
                const SizedBox(height: 3),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: isAdmin ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
