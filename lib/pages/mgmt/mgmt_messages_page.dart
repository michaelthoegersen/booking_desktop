import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/direct_chat_service.dart';
import '../../services/group_chat_service.dart';
import '../../state/active_company.dart';
import '../../widgets/mention_helpers.dart';
import '../../widgets/mgmt_shell.dart' show mgmtUnreadNotifier;

class MgmtMessagesPage extends StatefulWidget {
  const MgmtMessagesPage({super.key});

  @override
  State<MgmtMessagesPage> createState() => _MgmtMessagesPageState();
}

class _MgmtMessagesPageState extends State<MgmtMessagesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _sb = Supabase.instance.client;

  // Gig messages state
  String? _selectedGigId;

  // Chat state
  String? _selectedChatKey; // "dm:<peerId>" or "group:<groupId>"

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _markGigAsRead(String gigId) async {
    try {
      await _sb
          .from('gig_messages')
          .update({'read_by_admin': true})
          .eq('gig_id', gigId)
          .eq('is_admin', false);

      // Also clear notifications on mobile for this gig
      final uid = _sb.auth.currentUser?.id;
      if (uid != null) {
        await _sb
            .from('notifications')
            .update({'read': true})
            .eq('user_id', uid)
            .eq('read', false)
            .eq('gig_id', gigId)
            .inFilter('type', ['gig_chat', 'chat_mention']);
      }

      mgmtUnreadNotifier.value++;
    } catch (e) {
      debugPrint('Mark as read error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // Left panel: thread list with tabs
        SizedBox(
          width: 300,
          child: Column(
            children: [
              // Tab bar
              Container(
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: cs.outlineVariant)),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black45,
                  indicatorColor: Colors.black,
                  tabs: const [
                    Tab(text: 'DM'),
                    Tab(text: 'Aktivitet'),
                  ],
                ),
              ),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // Tab 1: DM + Groups
                    _ChatThreadList(
                      selectedKey: _selectedChatKey,
                      onSelect: (key) =>
                          setState(() => _selectedChatKey = key),
                      onDeleted: (key) {
                        if (_selectedChatKey == key) {
                          setState(() => _selectedChatKey = null);
                        }
                      },
                    ),

                    // Tab 2: Aktivitet messages
                    _GigThreadList(
                      selectedGigId: _selectedGigId,
                      onSelect: (gigId) {
                        setState(() => _selectedGigId = gigId);
                        _markGigAsRead(gigId);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1),

        // Right panel: conversation view
        Expanded(
          child: _tabCtrl.index == 0
              ? _selectedChatKey == null
                  ? const Center(
                      child: Text('Velg en samtale',
                          style: TextStyle(color: Colors.black45)))
                  : _selectedChatKey!.startsWith('dm:')
                      ? _DmChatView(
                          key: ValueKey(_selectedChatKey),
                          peerId: _selectedChatKey!.substring(3),
                        )
                      : _GroupChatView(
                          key: ValueKey(_selectedChatKey),
                          groupId: _selectedChatKey!.substring(6),
                        )
              : _selectedGigId == null
                  ? const Center(
                      child: Text('Velg en samtale',
                          style: TextStyle(color: Colors.black45)))
                  : _GigChatView(
                      key: ValueKey(_selectedGigId),
                      gigId: _selectedGigId!,
                    ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Chat thread list (DM + Groups) with new-chat button
// ===========================================================================

class _ChatThreadList extends StatefulWidget {
  final String? selectedKey;
  final void Function(String key) onSelect;
  final void Function(String key) onDeleted;

  const _ChatThreadList({
    required this.selectedKey,
    required this.onSelect,
    required this.onDeleted,
  });

  @override
  State<_ChatThreadList> createState() => _ChatThreadListState();
}

class _ChatThreadListState extends State<_ChatThreadList> {
  final _sb = Supabase.instance.client;
  String get _myId => _sb.auth.currentUser?.id ?? '';

  final Map<String, Map<String, dynamic>> _profileCache = {};

  // Read cursors for unread badges
  Map<String, DateTime> _dmCursors = {};
  Map<String, DateTime> _groupCursors = {};
  Map<String, int> _groupUnreads = {};

  @override
  void initState() {
    super.initState();
    _loadCursors();
    mgmtUnreadNotifier.addListener(_loadCursors);
  }

  @override
  void dispose() {
    mgmtUnreadNotifier.removeListener(_loadCursors);
    super.dispose();
  }

  Future<void> _loadCursors() async {
    try {
      final dmRes = await _sb
          .from('dm_read_cursors')
          .select('peer_id, last_read_at')
          .eq('user_id', _myId);
      _dmCursors = {};
      for (final r in (dmRes as List)) {
        _dmCursors[r['peer_id'] as String] =
            DateTime.parse(r['last_read_at'] as String);
      }

      final groupRes = await _sb
          .from('group_read_cursors')
          .select('group_chat_id, last_read_at')
          .eq('user_id', _myId);
      _groupCursors = {};
      for (final r in (groupRes as List)) {
        _groupCursors[r['group_chat_id'] as String] =
            DateTime.parse(r['last_read_at'] as String);
      }

      await _loadGroupUnreads();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Load cursors error: $e');
    }
  }

  Future<void> _loadGroupUnreads() async {
    try {
      final myGroups = await _sb
          .from('group_chat_members')
          .select('group_chat_id')
          .eq('user_id', _myId);
      final groupIds = (myGroups as List)
          .map((r) => r['group_chat_id'] as String)
          .toList();
      if (groupIds.isEmpty) {
        _groupUnreads = {};
        return;
      }

      final msgs = await _sb
          .from('group_chat_messages')
          .select('group_chat_id, created_at')
          .inFilter('group_chat_id', groupIds)
          .neq('user_id', _myId)
          .order('created_at', ascending: false)
          .limit(500);

      _groupUnreads = {};
      for (final msg in (msgs as List)) {
        final groupId = msg['group_chat_id'] as String;
        final createdAt = DateTime.parse(msg['created_at'] as String);
        final cursor = _groupCursors[groupId];
        if (cursor == null || createdAt.isAfter(cursor)) {
          _groupUnreads[groupId] = (_groupUnreads[groupId] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('Load group unreads error: $e');
    }
  }

  Future<void> _markDmRead(String peerId) async {
    final now = DateTime.now().toUtc();
    _dmCursors[peerId] = now;
    setState(() {});
    try {
      await _sb.from('dm_read_cursors').upsert({
        'user_id': _myId,
        'peer_id': peerId,
        'last_read_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Mark DM read error: $e');
    }
    mgmtUnreadNotifier.value++;
  }

  Future<void> _markGroupRead(String groupId) async {
    final now = DateTime.now().toUtc();
    _groupCursors[groupId] = now;
    _groupUnreads.remove(groupId);
    setState(() {});
    try {
      await _sb.from('group_read_cursors').upsert({
        'user_id': _myId,
        'group_chat_id': groupId,
        'last_read_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Mark group read error: $e');
    }
    mgmtUnreadNotifier.value++;
  }

  void _handleSelect(String key) {
    widget.onSelect(key);
    if (key.startsWith('dm:')) {
      _markDmRead(key.substring(3));
    } else if (key.startsWith('group:')) {
      _markGroupRead(key.substring(6));
    }
  }

  Future<Map<String, dynamic>> _getProfile(String peerId) async {
    if (_profileCache.containsKey(peerId)) return _profileCache[peerId]!;
    try {
      final res = await _sb
          .from('profiles')
          .select('id, name, avatar_url')
          .eq('id', peerId)
          .maybeSingle();
      final p =
          res ?? {'id': peerId, 'name': 'Unknown', 'avatar_url': null};
      _profileCache[peerId] = p;
      return p;
    } catch (_) {
      final f = {'id': peerId, 'name': 'Unknown', 'avatar_url': null};
      _profileCache[peerId] = f;
      return f;
    }
  }

  void _showNewChatSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Ny direktemelding'),
              onTap: () {
                Navigator.pop(ctx);
                _showContactPicker();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_rounded),
              title: const Text('Ny gruppe'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateGroupDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showContactPicker() async {
    // Load contacts from same company
    final myProfile = await _sb
        .from('profiles')
        .select('company_id')
        .eq('id', _myId)
        .maybeSingle();
    final companyId = myProfile?['company_id'];
    if (companyId == null) return;

    final members = await _sb
        .from('profiles')
        .select('id, name, avatar_url')
        .eq('company_id', companyId)
        .order('name');
    final contacts = List<Map<String, dynamic>>.from(members);
    contacts.removeWhere((p) => p['id'] == _myId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny direktemelding'),
        content: SizedBox(
          width: 350,
          height: 400,
          child: ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final c = contacts[i];
              final cName = (c['name'] ?? '').toString();
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.black,
                  backgroundImage: c['avatar_url'] != null &&
                          (c['avatar_url'] as String).isNotEmpty
                      ? NetworkImage(c['avatar_url'] as String)
                      : null,
                  child: c['avatar_url'] == null ||
                          (c['avatar_url'] as String).isEmpty
                      ? Text(
                          cName.isNotEmpty ? cName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
                title: Text(cName),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSelect('dm:${c['id']}');
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final Set<String> selected = {};
    List<Map<String, dynamic>> contacts = [];
    bool loading = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          // Load contacts on first build
          if (loading) {
            _sb
                .from('profiles')
                .select('company_id')
                .eq('id', _myId)
                .maybeSingle()
                .then((myProfile) {
              final companyId = myProfile?['company_id'];
              if (companyId == null) {
                setDialogState(() => loading = false);
                return;
              }
              _sb
                  .from('profiles')
                  .select('id, name, avatar_url')
                  .eq('company_id', companyId)
                  .order('name')
                  .then((res) {
                final list = List<Map<String, dynamic>>.from(res);
                list.removeWhere((p) => p['id'] == _myId);
                setDialogState(() {
                  contacts = list;
                  loading = false;
                });
              });
            });
          }

          return AlertDialog(
            title: const Text('Ny gruppe'),
            content: SizedBox(
              width: 400,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gruppenavn',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Velg medlemmer',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (_, i) {
                              final c = contacts[i];
                              final cId = c['id'] as String;
                              final cName = (c['name'] ?? '').toString();
                              final isSelected = selected.contains(cId);
                              return CheckboxListTile(
                                value: isSelected,
                                title: Text(cName),
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selected.add(cId);
                                    } else {
                                      selected.remove(cId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                onPressed: nameCtrl.text.trim().isEmpty || selected.isEmpty
                    ? null
                    : () async {
                        final groupId = await GroupChatService.createGroup(
                          nameCtrl.text.trim(),
                          selected.toList(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        widget.onSelect('group:$groupId');
                      },
                child: const Text('Opprett'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // "New chat" button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _showNewChatSheet,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ny samtale'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        // DM conversations
        Expanded(
          child: Builder(builder: (context) {
            final role = activeCompanyNotifier.value?.role;
            debugPrint('🔑 Chat admin check: role=$role');
            final isAdmin = role == 'admin' || role == 'management';

            void confirmDeleteDm(String peerId) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Slett samtale'),
                  content: const Text(
                      'Er du sikker på at du vil slette denne samtalen? Alle meldinger blir slettet permanent.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Avbryt'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await DirectChatService.deleteConversation(peerId);
                        widget.onDeleted('dm:$peerId');
                      },
                      child: const Text('Slett'),
                    ),
                  ],
                ),
              );
            }

            void confirmDeleteGroup(String groupId) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Slett gruppe'),
                  content: const Text(
                      'Er du sikker på at du vil slette denne gruppen? Alle meldinger og medlemmer blir slettet permanent.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Avbryt'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await GroupChatService.deleteGroup(groupId);
                        widget.onDeleted('group:$groupId');
                      },
                      child: const Text('Slett'),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              children: [
                // DMs
                _DmList(
                  myId: _myId,
                  getProfile: _getProfile,
                  selectedKey: widget.selectedKey,
                  onSelect: _handleSelect,
                  onDeleteConversation:
                      isAdmin ? confirmDeleteDm : null,
                  dmCursors: _dmCursors,
                ),

                // Groups
                _GroupList(
                  selectedKey: widget.selectedKey,
                  onSelect: _handleSelect,
                  onDeleteGroup:
                      isAdmin ? confirmDeleteGroup : null,
                  groupUnreads: _groupUnreads,
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DM list within chat tab
// ---------------------------------------------------------------------------

class _DmList extends StatelessWidget {
  final String myId;
  final Future<Map<String, dynamic>> Function(String) getProfile;
  final String? selectedKey;
  final void Function(String) onSelect;
  final void Function(String peerId)? onDeleteConversation;
  final Map<String, DateTime> dmCursors;

  const _DmList({
    required this.myId,
    required this.getProfile,
    required this.selectedKey,
    required this.onSelect,
    this.onDeleteConversation,
    this.dmCursors = const {},
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DirectChatService.streamAllMyMessages(),
      builder: (context, snapshot) {
        final allMessages = snapshot.data ?? [];
        if (allMessages.isEmpty) return const SizedBox.shrink();

        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final msg in allMessages) {
          final senderId = msg['sender_id'] as String? ?? '';
          final receiverId = msg['receiver_id'] as String? ?? '';
          final peerId = senderId == myId ? receiverId : senderId;
          grouped.putIfAbsent(peerId, () => []).add(msg);
        }

        final conversations = grouped.entries.map((e) {
          final msgs = e.value;
          msgs.sort((a, b) {
            final aTime = a['created_at'] as String? ?? '';
            final bTime = b['created_at'] as String? ?? '';
            return bTime.compareTo(aTime);
          });
          // Calculate unread: messages from peer that are newer than cursor
          final cursor = dmCursors[e.key];
          final unread = msgs.where((m) {
            if (m['sender_id'] == myId) return false;
            if (cursor == null) return true;
            final createdAt = DateTime.tryParse(m['created_at'] as String? ?? '');
            return createdAt != null && createdAt.isAfter(cursor);
          }).length;
          return MapEntry(e.key, (msgs.first, unread));
        }).toList();

        conversations.sort((a, b) {
          final aTime = a.value.$1['created_at'] as String? ?? '';
          final bTime = b.value.$1['created_at'] as String? ?? '';
          return bTime.compareTo(aTime);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Direktemeldinger',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38)),
            ),
            ...conversations.map((entry) {
              final key = 'dm:${entry.key}';
              final isSelected = selectedKey == key;
              return _DmTile(
                key: ValueKey(key),
                peerId: entry.key,
                lastMessage: entry.value.$1,
                unreadCount: entry.value.$2,
                myId: myId,
                getProfile: getProfile,
                isSelected: isSelected,
                onTap: () => onSelect(key),
                onDelete: onDeleteConversation != null
                    ? () => onDeleteConversation!(entry.key)
                    : null,
              );
            }),
          ],
        );
      },
    );
  }
}

class _DmTile extends StatefulWidget {
  final String peerId;
  final Map<String, dynamic> lastMessage;
  final int unreadCount;
  final String myId;
  final Future<Map<String, dynamic>> Function(String) getProfile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _DmTile({
    super.key,
    required this.peerId,
    required this.lastMessage,
    this.unreadCount = 0,
    required this.myId,
    required this.getProfile,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<_DmTile> createState() => _DmTileState();
}

class _DmTileState extends State<_DmTile> {
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
    final message = widget.lastMessage['message'] as String? ?? '';
    final isMine = widget.lastMessage['sender_id'] == widget.myId;
    final timeStr = _fmtTime(widget.lastMessage['created_at'] as String?);

    return InkWell(
      onTap: widget.onTap,
      onSecondaryTapUp: widget.onDelete == null
          ? null
          : (details) {
              final pos = details.globalPosition;
              showMenu(
                context: context,
                position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
                items: [
                  PopupMenuItem(
                    onTap: widget.onDelete,
                    child: const Text('Slett samtale',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              );
            },
      child: Container(
        color: widget.isSelected ? Colors.black : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person, size: 18,
                color: widget.isSelected ? Colors.white54 : Colors.black38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName.isEmpty ? '...' : peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: widget.isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isMine ? 'Du: $message' : message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isSelected
                          ? Colors.white60
                          : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timeStr != null)
                  Text(timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            widget.isSelected ? Colors.white54 : Colors.black38,
                      )),
                if (widget.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          widget.isSelected ? Colors.white : Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.unreadCount > 99
                          ? '99+'
                          : '${widget.unreadCount}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color:
                            widget.isSelected ? Colors.red : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
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
      if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
      if (diff.inDays == 1) return 'I går';
      if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
      return DateFormat('dd.MM.yy').format(dt);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Group list within chat tab
// ---------------------------------------------------------------------------

class _GroupList extends StatelessWidget {
  final String? selectedKey;
  final void Function(String) onSelect;
  final void Function(String groupId)? onDeleteGroup;
  final Map<String, int> groupUnreads;

  const _GroupList({
    required this.selectedKey,
    required this.onSelect,
    this.onDeleteGroup,
    this.groupUnreads = const {},
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: GroupChatService.streamMyGroups(),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? [];
        if (groups.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Grupper',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38)),
            ),
            ...groups.map((g) {
              final groupId = g['id'] as String;
              final key = 'group:$groupId';
              final isSelected = selectedKey == key;
              final unread = groupUnreads[groupId] ?? 0;
              return InkWell(
                onTap: () => onSelect(key),
                onSecondaryTapUp: onDeleteGroup == null
                    ? null
                    : (details) {
                        final pos = details.globalPosition;
                        showMenu(
                          context: context,
                          position: RelativeRect.fromLTRB(
                              pos.dx, pos.dy, pos.dx, pos.dy),
                          items: [
                            PopupMenuItem(
                              onTap: () => onDeleteGroup!(groupId),
                              child: const Text('Slett gruppe',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        );
                      },
                child: Container(
                  color: isSelected ? Colors.black : Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.group, size: 18,
                          color: isSelected ? Colors.white54 : Colors.black38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g['name'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color:
                                isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
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
            }),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// DM chat view (right panel)
// ===========================================================================

class _DmChatView extends StatefulWidget {
  final String peerId;
  const _DmChatView({super.key, required this.peerId});

  @override
  State<_DmChatView> createState() => _DmChatViewState();
}

class _DmChatViewState extends State<_DmChatView> with MentionMixin {
  final _sb = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _peerName;
  String? _senderName;
  String? _editingMessageId;
  Map<String, dynamic>? _replyTo;
  DateTime? _peerLastReadAt;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => onMentionTextChanged(_controller));
    _load();
  }

  Future<void> _load() async {
    final peer = await _sb
        .from('profiles')
        .select('name')
        .eq('id', widget.peerId)
        .maybeSingle();
    _peerName = peer?['name'] as String? ?? '';
    _senderName = await DirectChatService.getSenderName();
    // In DM, the only mention candidate is the peer
    initMentionCandidates([
      MentionCandidate(id: widget.peerId, name: _peerName ?? ''),
    ]);
    // Load peer's read cursor (when they last read MY messages)
    _loadPeerReadCursor();
    if (mounted) setState(() {});
  }

  Future<void> _loadPeerReadCursor() async {
    try {
      final myId = _sb.auth.currentUser?.id;
      if (myId == null) return;
      final row = await _sb
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
    super.dispose();
  }

  void _startEdit(Map<String, dynamic> msg) {
    setState(() {
      _editingMessageId = msg['id'] as String;
      _replyTo = null;
      _controller.text = msg['message'] as String? ?? '';
    });
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() {
      _replyTo = msg;
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _cancelEdit() {
    setState(() { _editingMessageId = null; _controller.clear(); });
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _senderName == null) return;
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
          senderName: _senderName!,
          replyToId: _replyTo?['id'] as String?,
          mentionedUserIds: mentions.isNotEmpty ? mentions : null,
        );
        clearMentions();
        setState(() => _replyTo = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showConvertToGroupDialog(BuildContext context) async {
    final groupNameController = TextEditingController(text: _peerName ?? '');
    final selectedIds = <String>{};
    List<Map<String, dynamic>> contacts = [];

    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId != null) {
        final rows = await _sb.rpc(
          'get_company_member_profiles',
          params: {'p_company_id': companyId},
        );
        final myId = _sb.auth.currentUser?.id;
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myId = _sb.auth.currentUser?.id ?? '';

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _peerName ?? '...',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
                  child: Text('Ingen meldinger',
                      style: TextStyle(color: Colors.black45)),
                );
              }
              // Find the last message sent by me that the peer has read
              String? lastReadMsgId;
              if (_peerLastReadAt != null) {
                for (final m in messages) {
                  if (m['sender_id'] == myId) {
                    final ca = m['created_at'] as String?;
                    if (ca != null) {
                      final dt = DateTime.parse(ca);
                      if (!dt.isAfter(_peerLastReadAt!)) {
                        lastReadMsgId = m['id'] as String?;
                        break; // messages are reverse-sorted, first match is latest read
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
                  final isMine = msg['sender_id'] == myId;

                  Map<String, dynamic>? replyMsg;
                  final replyToId = msg['reply_to_id'];
                  if (replyToId != null) {
                    replyMsg = messages.cast<Map<String, dynamic>?>().firstWhere(
                      (m) => m?['id'] == replyToId,
                      orElse: () => null,
                    );
                  }

                  return _Bubble(
                    message: msg['message'] as String? ?? '',
                    senderName: msg['sender_name'] as String? ?? '',
                    isAdmin: isMine,
                    createdAt: msg['created_at'] as String?,
                    editedAt: msg['edited_at'] as String?,
                    replyMsg: replyMsg,
                    onReply: () => _startReply(msg),
                    onEdit: isMine ? () => _startEdit(msg) : null,
                    showRead: isMine && msg['id'] == lastReadMsgId,
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

        // Input
        _ChatInput(
          controller: _controller,
          sending: _sending,
          onSend: _send,
          editingMessageId: _editingMessageId,
          replyTo: _replyTo,
          onCancelEdit: _cancelEdit,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }
}

// ===========================================================================
// Group chat view (right panel)
// ===========================================================================

class _GroupChatView extends StatefulWidget {
  final String groupId;
  const _GroupChatView({super.key, required this.groupId});

  @override
  State<_GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<_GroupChatView> with MentionMixin {
  final _sb = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _senderName;
  String _groupName = '';
  String? _editingMessageId;
  Map<String, dynamic>? _replyTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => onMentionTextChanged(_controller));
    _load();
  }

  Future<void> _load() async {
    _senderName = await DirectChatService.getSenderName();
    final group = await _sb
        .from('group_chats')
        .select('name')
        .eq('id', widget.groupId)
        .maybeSingle();
    _groupName = group?['name'] as String? ?? '';
    // Load group members as mention candidates
    try {
      final members = await GroupChatService.getGroupMembers(widget.groupId);
      final myId = _sb.auth.currentUser?.id;
      final candidates = members
          .where((m) => m['user_id'] != myId)
          .map((m) {
            final profile = m['profiles'] as Map<String, dynamic>?;
            return MentionCandidate(
              id: m['user_id'] as String,
              name: profile?['name'] as String? ?? '',
            );
          })
          .where((c) => c.name.isNotEmpty)
          .toList();
      initMentionCandidates(candidates);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startEdit(Map<String, dynamic> msg) {
    setState(() {
      _editingMessageId = msg['id'] as String;
      _replyTo = null;
      _controller.text = msg['message'] as String? ?? '';
    });
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() {
      _replyTo = msg;
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _cancelEdit() {
    setState(() { _editingMessageId = null; _controller.clear(); });
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _senderName == null) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      if (_editingMessageId != null) {
        await GroupChatService.updateGroupMessage(_editingMessageId!, text);
        setState(() => _editingMessageId = null);
      } else {
        final mentions = List<String>.from(mentionedUserIds);
        await GroupChatService.sendGroupMessage(
          groupId: widget.groupId,
          message: text,
          senderName: _senderName!,
          replyToId: _replyTo?['id'] as String?,
          mentionedUserIds: mentions.isNotEmpty ? mentions : null,
        );
        clearMentions();
        setState(() => _replyTo = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myId = _sb.auth.currentUser?.id ?? '';

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              const Icon(Icons.group, size: 20, color: Colors.black45),
              const SizedBox(width: 8),
              Text(
                _groupName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: GroupChatService.streamGroupMessages(widget.groupId),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                return const Center(
                  child: Text('Ingen meldinger',
                      style: TextStyle(color: Colors.black45)),
                );
              }
              return ListView.separated(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(20),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final msg = messages[i];
                  final isMine = msg['user_id'] == myId;

                  Map<String, dynamic>? replyMsg;
                  final replyToId = msg['reply_to_id'];
                  if (replyToId != null) {
                    replyMsg = messages.cast<Map<String, dynamic>?>().firstWhere(
                      (m) => m?['id'] == replyToId,
                      orElse: () => null,
                    );
                  }

                  return _Bubble(
                    message: msg['message'] as String? ?? '',
                    senderName: msg['sender_name'] as String? ?? '',
                    isAdmin: isMine,
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

        // Input
        _ChatInput(
          controller: _controller,
          sending: _sending,
          onSend: _send,
          editingMessageId: _editingMessageId,
          replyTo: _replyTo,
          onCancelEdit: _cancelEdit,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }
}

// ===========================================================================
// Shared chat input bar
// ===========================================================================

class _ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final String? editingMessageId;
  final Map<String, dynamic>? replyTo;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onCancelReply;

  const _ChatInput({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.editingMessageId,
    this.replyTo,
    this.onCancelEdit,
    this.onCancelReply,
  });

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply preview bar
        if (widget.replyTo != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Container(width: 3, height: 36, decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(2),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.replyTo!['sender_name'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(_truncate(widget.replyTo!['message'] as String? ?? '', 60),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onCancelReply),
              ],
            ),
          ),

        // Edit indicator
        if (widget.editingMessageId != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            color: const Color(0xFFFFF9C4),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                const Text('Redigerer melding', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onCancelEdit),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
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
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              widget.sending
                  ? const SizedBox(
                      width: 44, height: 44,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: widget.onSend,
                      icon: Icon(
                        widget.editingMessageId != null ? Icons.check_rounded : Icons.send_rounded,
                        size: 18,
                      ),
                      label: Text(widget.editingMessageId != null ? 'Lagre' : 'Send'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Gig thread list (existing functionality, unchanged)
// ===========================================================================

class _GigThreadList extends StatelessWidget {
  final String? selectedGigId;
  final void Function(String gigId) onSelect;

  const _GigThreadList(
      {required this.selectedGigId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sb = Supabase.instance.client;

    return StreamBuilder<List<Map<String, dynamic>>>(
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
              child: Text('Ingen meldinger ennå',
                  style: TextStyle(color: Colors.black45)),
            ),
          );
        }

        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final m in messages) {
          final gid = m['gig_id'] as String;
          grouped.putIfAbsent(gid, () => []).add(m);
        }

        final threads = grouped.entries.toList()
          ..sort((a, b) {
            final aLast = a.value.last['created_at'] as String? ?? '';
            final bLast = b.value.last['created_at'] as String? ?? '';
            return bLast.compareTo(aLast);
          });

        return ListView.separated(
          itemCount: threads.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: cs.outlineVariant),
          itemBuilder: (context, i) {
            final gigId = threads[i].key;
            final msgs = threads[i].value;
            final last = msgs.last;
            final isSelected = selectedGigId == gigId;
            final unread = msgs
                .where((r) =>
                    r['is_admin'] != true && r['read_by_admin'] != true)
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
        final venueName =
            gigSnap.data?['venue_name'] as String? ?? 'Ukjent sted';
        final dateFrom = gigSnap.data?['date_from'] as String?;
        final dateStr = _fmtDate(dateFrom);
        final timeStr = _fmtTime(lastAt);

        return InkWell(
          onTap: onTap,
          child: Container(
            color: isSelected ? Colors.black : Colors.transparent,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          color:
                              isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    if (timeStr != null)
                      Text(timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white60
                                : Colors.black38,
                          )),
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
                          color:
                              isSelected ? Colors.white70 : Colors.black54,
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

// ===========================================================================
// Gig chat view (existing, unchanged)
// ===========================================================================

class _GigChatView extends StatefulWidget {
  final String gigId;
  const _GigChatView({super.key, required this.gigId});

  @override
  State<_GigChatView> createState() => _GigChatViewState();
}

class _GigChatViewState extends State<_GigChatView> with MentionMixin {
  final _sb = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  Map<String, dynamic>? _gig;
  String? _editingMessageId;
  Map<String, dynamic>? _replyTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => onMentionTextChanged(_controller));
    _loadGig();
    _loadMentionCandidates();
  }

  Future<void> _loadGig() async {
    final gig = await _sb
        .from('gigs')
        .select('venue_name, city, date_from')
        .eq('id', widget.gigId)
        .maybeSingle();
    if (mounted) setState(() => _gig = gig);
  }

  Future<void> _loadMentionCandidates() async {
    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId == null) return;
      final rows = await _sb.rpc(
        'get_company_member_profiles',
        params: {'p_company_id': companyId},
      );
      final myId = _sb.auth.currentUser?.id;
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startEdit(Map<String, dynamic> msg) {
    setState(() {
      _editingMessageId = msg['id'] as String;
      _replyTo = null;
      _controller.text = msg['message'] as String? ?? '';
    });
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() {
      _replyTo = msg;
      _editingMessageId = null;
      _controller.clear();
    });
  }

  void _cancelEdit() {
    setState(() { _editingMessageId = null; _controller.clear(); });
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
        // Update gig message via Supabase directly (admin may not be user_id owner)
        await _sb.from('gig_messages').update({
          'message': text,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _editingMessageId!);
        setState(() => _editingMessageId = null);
      } else {
        final user = _sb.auth.currentUser;
        final name = user?.userMetadata?['name'] as String? ?? 'Admin';
        final mentions = List<String>.from(mentionedUserIds);
        await _sb.from('gig_messages').insert({
          'gig_id': widget.gigId,
          'user_id': user?.id,
          'sender_name': name,
          'message': text,
          'is_admin': true,
          if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
          if (mentions.isNotEmpty) 'mentioned_user_ids': mentions,
        });
        clearMentions();
        setState(() => _replyTo = null);

        // Push notification to gig participants
        try {
          final gig = await _sb
              .from('gigs')
              .select('company_id')
              .eq('id', widget.gigId)
              .maybeSingle();
          if (gig != null) {
            await _sb.functions.invoke('notify-chat', body: {
              'type': 'gig',
              'gig_id': widget.gigId,
              'company_id': gig['company_id'],
              'sender_id': user?.id,
              'sender_name': name,
              'message': text,
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil ved sending: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(venue,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              if (dateStr.isNotEmpty)
                Text(dateStr,
                    style:
                        const TextStyle(color: Colors.black45, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _sb
                .from('gig_messages')
                .stream(primaryKey: ['id'])
                .eq('gig_id', widget.gigId)
                .order('created_at'),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                return const Center(
                  child: Text('Ingen meldinger',
                      style: TextStyle(color: Colors.black45)),
                );
              }
              final myId = _sb.auth.currentUser?.id ?? '';
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

                  return _Bubble(
                    message: msg['message'] as String? ?? '',
                    senderName: msg['sender_name'] as String? ?? '',
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
        _ChatInput(
          controller: _controller,
          sending: _sending,
          onSend: _send,
          editingMessageId: _editingMessageId,
          replyTo: _replyTo,
          onCancelEdit: _cancelEdit,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }
}

// ===========================================================================
// Chat bubble (shared)
// ===========================================================================

class _Bubble extends StatelessWidget {
  final String message;
  final String senderName;
  final bool isAdmin;
  final String? createdAt;
  final String? editedAt;
  final Map<String, dynamic>? replyMsg;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final bool showRead;

  const _Bubble({
    required this.message,
    required this.senderName,
    required this.isAdmin,
    this.createdAt,
    this.editedAt,
    this.replyMsg,
    this.onReply,
    this.onEdit,
    this.showRead = false,
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
          onSecondaryTapUp: (details) => _showContextMenu(context),
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
                Text(senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isAdmin ? Colors.white60 : Colors.black45,
                    )),
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
                        Text(replyMsg!['sender_name'] as String? ?? '',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: isAdmin ? Colors.white70 : Colors.black54)),
                        Text(_truncate(replyMsg!['message'] as String? ?? '', 60),
                          style: TextStyle(fontSize: 12,
                            color: isAdmin ? Colors.white54 : Colors.black45),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
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
                      Text(timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: isAdmin ? Colors.white38 : Colors.black38,
                          )),
                      if (editedAt != null) ...[
                        const SizedBox(width: 4),
                        Text('(redigert)',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isAdmin ? Colors.white38 : Colors.black38,
                          )),
                      ],
                      if (showRead && isAdmin) ...[
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
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
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
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('Kopier')]),
        ),
        if (onReply != null)
          const PopupMenuItem<String>(
            value: 'reply',
            child: Row(children: [Icon(Icons.reply, size: 18), SizedBox(width: 8), Text('Svar')]),
          ),
        if (onEdit != null)
          const PopupMenuItem<String>(
            value: 'edit',
            child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Rediger')]),
          ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: message));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
        );
      }
      if (value == 'reply') onReply?.call();
      if (value == 'edit') onEdit?.call();
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
