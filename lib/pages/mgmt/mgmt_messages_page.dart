import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';
import '../../widgets/mgmt_shell.dart' show mgmtUnreadNotifier;

class MgmtMessagesPage extends StatefulWidget {
  const MgmtMessagesPage({super.key});

  @override
  State<MgmtMessagesPage> createState() => _MgmtMessagesPageState();
}

class _MgmtMessagesPageState extends State<MgmtMessagesPage> {
  final _sb = Supabase.instance.client;
  String? _selectedGigId;

  Future<void> _markAsRead(String gigId) async {
    try {
      await _sb
          .from('gig_messages')
          .update({'read_by_admin': true})
          .eq('gig_id', gigId)
          .eq('is_admin', false);
      // Notify sidebar badge immediately
      mgmtUnreadNotifier.value++;
    } catch (e) {
      debugPrint('Mark as read error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Venstre: tråd-liste per gig
        SizedBox(
          width: 300,
          child: _GigThreadList(
            selectedGigId: _selectedGigId,
            onSelect: (gigId) {
              setState(() => _selectedGigId = gigId);
              _markAsRead(gigId);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        // Høyre: samtale
        Expanded(
          child: _selectedGigId == null
              ? const Center(
                  child: Text(
                    'Velg en samtale',
                    style: TextStyle(color: Colors.black45),
                  ),
                )
              : _GigChatView(
                  key: ValueKey(_selectedGigId),
                  gigId: _selectedGigId!,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tråd-liste (venstre panel) — henter gigs som har meldinger
// ---------------------------------------------------------------------------

class _GigThreadList extends StatelessWidget {
  final String? selectedGigId;
  final void Function(String gigId) onSelect;

  const _GigThreadList({required this.selectedGigId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CssTheme.outline)),
          ),
          child: const Text(
            'Messages',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: sb
                .from('gig_messages')
                .stream(primaryKey: ['id']).order('created_at'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
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

              // Grupper per gig_id
              final Map<String, List<Map<String, dynamic>>> grouped = {};
              for (final m in messages) {
                final gid = m['gig_id'] as String;
                grouped.putIfAbsent(gid, () => []).add(m);
              }

              // Sorter tråder etter siste melding
              final threads = grouped.entries.toList()
                ..sort((a, b) {
                  final aLast = a.value.last['created_at'] as String? ?? '';
                  final bLast = b.value.last['created_at'] as String? ?? '';
                  return bLast.compareTo(aLast);
                });

              return ListView.separated(
                itemCount: threads.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: CssTheme.outline),
                itemBuilder: (context, i) {
                  final gigId = threads[i].key;
                  final msgs = threads[i].value;
                  final last = msgs.last;
                  final isSelected = selectedGigId == gigId;

                  final unread = msgs
                      .where((r) =>
                          r['is_admin'] != true &&
                          r['read_by_admin'] != true)
                      .length;

                  return _GigThreadTile(
                    gigId: gigId,
                    lastMessage: last['message'] as String? ?? '',
                    lastSender: last['sender_name'] as String? ?? '',
                    lastAt: last['created_at'] as String? ?? '',
                    messageCount: msgs.length,
                    unreadCount: unread,
                    isSelected: isSelected,
                    onTap: () => onSelect(gigId),
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

class _GigThreadTile extends StatelessWidget {
  final String gigId;
  final String lastMessage;
  final String lastSender;
  final String lastAt;
  final int messageCount;
  final int unreadCount;
  final bool isSelected;
  final VoidCallback onTap;

  const _GigThreadTile({
    required this.gigId,
    required this.lastMessage,
    required this.lastSender,
    required this.lastAt,
    required this.messageCount,
    this.unreadCount = 0,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;

    return FutureBuilder<Map<String, dynamic>?>(
      future: sb
          .from('gigs')
          .select('venue_name, city, date_from')
          .eq('id', gigId)
          .maybeSingle(),
      builder: (context, gigSnap) {
        final venueName = gigSnap.data?['venue_name'] as String? ?? 'Ukjent sted';
        final dateFrom = gigSnap.data?['date_from'] as String?;
        final dateStr = _fmtDate(dateFrom);
        final timeStr = _fmtTime(lastAt);

        return InkWell(
          onTap: onTap,
          child: Container(
            color: isSelected ? Colors.black : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${dateStr ?? ''} · $venueName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    if (timeStr != null)
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white60 : Colors.black38,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$lastSender: $lastMessage',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.red : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _fmtDate(String? iso) {
    if (iso == null) return null;
    try {
      return DateFormat('dd.MM.yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
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

// ---------------------------------------------------------------------------
// Samtalevisning (høyre panel)
// ---------------------------------------------------------------------------

class _GigChatView extends StatefulWidget {
  final String gigId;

  const _GigChatView({super.key, required this.gigId});

  @override
  State<_GigChatView> createState() => _GigChatViewState();
}

class _GigChatViewState extends State<_GigChatView> {
  final _sb = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  Map<String, dynamic>? _gig;

  @override
  void initState() {
    super.initState();
    _loadGig();
  }

  Future<void> _loadGig() async {
    final gig = await _sb
        .from('gigs')
        .select('venue_name, city, date_from')
        .eq('id', widget.gigId)
        .maybeSingle();
    if (mounted) setState(() => _gig = gig);
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
      final user = _sb.auth.currentUser;
      final name =
          user?.userMetadata?['name'] as String? ?? 'Admin';
      await _sb.from('gig_messages').insert({
        'gig_id': widget.gigId,
        'user_id': user?.id,
        'sender_name': name,
        'message': text,
        'is_admin': true,
      });
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
    final venueName = _gig?['venue_name'] as String? ?? '';
    final cityName = _gig?['city'] as String? ?? '';
    final venueParts = [venueName, cityName].where((s) => s.isNotEmpty);
    final venue = venueParts.isNotEmpty ? venueParts.join(' · ') : '...';
    final dateFrom = _gig?['date_from'] as String?;
    String dateStr = '';
    if (dateFrom != null) {
      try {
        dateStr = DateFormat('dd.MM.yyyy').format(DateTime.parse(dateFrom));
      } catch (_) {
        dateStr = dateFrom;
      }
    }

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CssTheme.outline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                venue,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.black45, fontSize: 13),
                ),
            ],
          ),
        ),

        // Meldingsliste
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _sb
                .from('gig_messages')
                .stream(primaryKey: ['id'])
                .eq('gig_id', widget.gigId)
                .order('created_at'),
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
                  return _Bubble(
                    message: msg['message'] as String? ?? '',
                    senderName: msg['sender_name'] as String? ?? '',
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
    );
  }
}

// ---------------------------------------------------------------------------
// Chat-boble
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  final String message;
  final String senderName;
  final bool isAdmin;
  final String? createdAt;

  const _Bubble({
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
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return null;
    }
  }
}
