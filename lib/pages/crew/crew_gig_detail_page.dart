import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CrewGigDetailPage extends StatefulWidget {
  final String gigId;

  const CrewGigDetailPage({super.key, required this.gigId});

  @override
  State<CrewGigDetailPage> createState() => _CrewGigDetailPageState();
}

class _CrewGigDetailPageState extends State<CrewGigDetailPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _gig;
  String? _myStatus; // 'pending', 'available', 'unavailable'
  String? _myRole;
  List<_MemberAvailability> _members = [];

  // Per-show crew assignment (admin / gruppeleder only)
  List<Map<String, dynamic>> _shows = [];
  List<Map<String, dynamic>> _companyMembers = [];
  Map<String, Set<String>> _selectedSkarpByShow = {};
  Map<String, Set<String>> _selectedBassByShow = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1. Gig info
      final gig = await _sb
          .from('gigs')
          .select('*')
          .eq('id', widget.gigId)
          .maybeSingle();
      _gig = gig;

      final companyId = gig?['company_id'] as String?;
      final uid = _sb.auth.currentUser?.id;

      // 2. Team members from profiles (same source as Settings)
      List<Map<String, dynamic>> members = [];
      if (companyId != null) {
        members = List<Map<String, dynamic>>.from(
          await _sb
              .from('profiles')
              .select('id, name, role, section')
              .eq('company_id', companyId),
        );
      }

      // Determine current user's role
      _myRole = null;
      if (uid != null) {
        for (final m in members) {
          if (m['id'] == uid) {
            _myRole = m['role'] as String?;
            break;
          }
        }
      }

      // 3. Availability for this gig
      final avail = await _sb
          .from('gig_availability')
          .select('user_id, status')
          .eq('gig_id', widget.gigId);
      final availMap = <String, String>{};
      for (final a in (avail as List)) {
        availMap[a['user_id'] as String] = a['status'] as String;
      }

      // 4. Build member list
      final memberList = <_MemberAvailability>[];
      for (final m in members) {
        final userId = m['id'] as String;
        memberList.add(_MemberAvailability(
          userId: userId,
          name: m['name'] as String? ?? '',
          role: m['role'] as String? ?? 'bruker',
          status: availMap[userId] ?? 'pending',
        ));
      }
      memberList.sort((a, b) => a.name.compareTo(b.name));

      _members = memberList;
      _myStatus = uid != null ? (availMap[uid] ?? 'pending') : 'pending';

      // 5. Shows & lineup for crew assignment (admin / gruppeleder)
      final isManager = _myRole == 'admin' ||
          _myRole == 'gruppeleder_skarp' ||
          _myRole == 'gruppeleder_bass';
      if (isManager) {
        final shows = await _sb
            .from('gig_shows')
            .select('*')
            .eq('gig_id', widget.gigId)
            .order('sort_order');
        _shows = List<Map<String, dynamic>>.from(shows);

        _companyMembers = members.map((m) {
          final mUid = m['id'] as String;
          return {
            'user_id': mUid,
            'name': m['name'] as String? ?? '',
            'section': m['section'] as String?,
            'status': availMap[mUid] ?? 'pending',
          };
        }).toList();
        _companyMembers.sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));

        final lineupData = await _sb
            .from('gig_lineup')
            .select('user_id, section, show_id')
            .eq('gig_id', widget.gigId);
        _selectedSkarpByShow = {};
        _selectedBassByShow = {};
        for (final l in List<Map<String, dynamic>>.from(lineupData)) {
          final showId = l['show_id'] as String? ?? '';
          if (l['section'] == 'skarp') {
            _selectedSkarpByShow.putIfAbsent(showId, () => {});
            _selectedSkarpByShow[showId]!.add(l['user_id'] as String);
          } else if (l['section'] == 'bass') {
            _selectedBassByShow.putIfAbsent(showId, () => {});
            _selectedBassByShow[showId]!.add(l['user_id'] as String);
          }
        }
      } else {
        _shows = [];
        _companyMembers = [];
        _selectedSkarpByShow = {};
        _selectedBassByShow = {};
      }
    } catch (e) {
      debugPrint('CrewGigDetail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setAvailability(String status) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _sb.from('gig_availability').upsert(
        {
          'gig_id': widget.gigId,
          'user_id': uid,
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'gig_id,user_id',
      );
      await _load();
    } catch (e) {
      debugPrint('Set availability error: $e');
    }
  }

  // ── Lineup helpers (admin / gruppeleder) ──

  bool get _isManager =>
      _myRole == 'admin' ||
      _myRole == 'gruppeleder_skarp' ||
      _myRole == 'gruppeleder_bass';

  void _toggleLineupMember(String userId, String section, String showId) {
    setState(() {
      final map =
          section == 'skarp' ? _selectedSkarpByShow : _selectedBassByShow;
      map.putIfAbsent(showId, () => {});
      final set = map[showId]!;
      if (set.contains(userId)) {
        set.remove(userId);
      } else {
        set.add(userId);
      }
    });
  }

  void _copyToAllShows(String fromShowId) {
    setState(() {
      final showIds = _shows.map((s) => s['id'] as String).toList();
      for (final section in ['skarp', 'bass']) {
        final map = section == 'skarp'
            ? _selectedSkarpByShow
            : _selectedBassByShow;
        final source = Set<String>.from(map[fromShowId] ?? {});
        for (final sid in showIds) {
          map[sid] = Set<String>.from(source);
        }
      }
    });
  }

  Future<void> _saveLineup(String section) async {
    final map =
        section == 'skarp' ? _selectedSkarpByShow : _selectedBassByShow;
    await _sb
        .from('gig_lineup')
        .delete()
        .eq('gig_id', widget.gigId)
        .eq('section', section);
    final rows = <Map<String, dynamic>>[];
    for (final entry in map.entries) {
      final showId = entry.key;
      for (final uid in entry.value) {
        rows.add({
          'gig_id': widget.gigId,
          'user_id': uid,
          'section': section,
          if (showId.isNotEmpty) 'show_id': showId,
        });
      }
    }
    if (rows.isNotEmpty) {
      await _sb.from('gig_lineup').insert(rows);
    }
  }

  Future<void> _saveAllLineup() async {
    try {
      await _saveLineup('skarp');
      await _saveLineup('bass');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lagret!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_gig == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Gig ikke funnet'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/c'),
              child: const Text('Tilbake'),
            ),
          ],
        ),
      );
    }

    final dateFrom = _gig!['date_from'] as String?;
    final dateTo = _gig!['date_to'] as String?;
    final venue = _gig!['venue_name'] as String? ?? '';
    final city = _gig!['city'] as String? ?? '';
    final gigType = _gig!['type'] as String? ?? 'gig';
    final isRehearsal = gigType == 'rehearsal';

    String dateLabel = '';
    if (dateFrom != null) {
      final df = DateFormat('dd.MM.yyyy');
      final from = df.format(DateTime.parse(dateFrom));
      if (dateTo != null && dateTo != dateFrom) {
        dateLabel = '$from – ${df.format(DateTime.parse(dateTo))}';
      } else {
        dateLabel = from;
      }
    }

    final title = isRehearsal
        ? 'Øvelse'
        : [venue, city].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb
          GestureDetector(
            onTap: () => context.go('/c'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  'Gigs',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : dateLabel,
                      style: Theme.of(context).textTheme.headlineMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dateLabel.isNotEmpty)
                      Text(
                        dateLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (isRehearsal)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Øvelse',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Gig info section
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Times section
                  _infoSection(cs, [
                    if (_gig!['meeting_time'] != null)
                      _infoRow(cs, 'Møtetid', _gig!['meeting_time']),
                    if (_gig!['get_in_time'] != null)
                      _infoRow(cs, 'Get-in', _gig!['get_in_time']),
                    if (_gig!['rehearsal_time'] != null)
                      _infoRow(cs, 'Lydprøve', _gig!['rehearsal_time']),
                    if (_gig!['performance_time'] != null)
                      _infoRow(cs, 'Spilletid', _gig!['performance_time']),
                    if (_gig!['get_out_time'] != null)
                      _infoRow(cs, 'Get-out', _gig!['get_out_time']),
                    if (_gig!['meeting_notes'] != null &&
                        (_gig!['meeting_notes'] as String).isNotEmpty)
                      _infoRow(cs, 'Notater', _gig!['meeting_notes']),
                  ]),

                  const SizedBox(height: 24),

                  // Availability buttons
                  Text('Din tilgjengelighet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AvailButton(
                          label: 'Kan',
                          icon: Icons.check_circle,
                          color: Colors.green,
                          selected: _myStatus == 'available',
                          onTap: () => _setAvailability('available'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AvailButton(
                          label: 'Kan ikke',
                          icon: Icons.cancel,
                          color: Colors.red,
                          selected: _myStatus == 'unavailable',
                          onTap: () => _setAvailability('unavailable'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // All members availability
                  Text('Crew-status',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_members.isEmpty)
                    Text('Ingen crew-medlemmer.',
                        style: TextStyle(color: cs.onSurfaceVariant))
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: _members.asMap().entries.map((entry) {
                          final i = entry.key;
                          final m = entry.value;
                          final isLast = i == _members.length - 1;

                          IconData statusIcon;
                          Color statusColor;
                          switch (m.status) {
                            case 'available':
                              statusIcon = Icons.check_circle;
                              statusColor = Colors.green;
                              break;
                            case 'unavailable':
                              statusIcon = Icons.cancel;
                              statusColor = Colors.red;
                              break;
                            default:
                              statusIcon = Icons.help_outline;
                              statusColor = Colors.grey;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                          color: cs.outlineVariant)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.surfaceContainerLow,
                                  child: Text(
                                    m.name.isNotEmpty
                                        ? m.name.characters.first
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    m.name.isNotEmpty ? m.name : 'Ukjent',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Icon(statusIcon,
                                    color: statusColor, size: 22),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // ── Per-show crew assignment (admin / gruppeleder) ──
                  if (_isManager && _shows.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Sett opp crew per show',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _saveAllLineup,
                          icon: const Icon(Icons.save, size: 16),
                          label: const Text('Lagre'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final show in _shows) ...[
                      _buildShowAssignment(context, show),
                      const SizedBox(height: 14),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowAssignment(
      BuildContext context, Map<String, dynamic> show) {
    final cs = Theme.of(context).colorScheme;
    final showId = show['id'] as String;
    final showName = show['show_name'] as String? ?? 'Show';

    final skarpMembers =
        _companyMembers.where((m) => m['section'] == 'skarp').toList();
    final bassMembers =
        _companyMembers.where((m) => m['section'] == 'bass').toList();
    final skarpSelected = _selectedSkarpByShow[showId] ?? {};
    final bassSelected = _selectedBassByShow[showId] ?? {};

    final lockedSkarp = _gig?['lineup_locked_skarp'] == true;
    final lockedBass = _gig?['lineup_locked_bass'] == true;
    // gruppeleder_skarp can only edit skarp, gruppeleder_bass only bass
    final canEditSkarp =
        _myRole == 'admin' || _myRole == 'gruppeleder_skarp';
    final canEditBass =
        _myRole == 'admin' || _myRole == 'gruppeleder_bass';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(showName,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (_shows.length > 1)
                GestureDetector(
                  onTap: () => _copyToAllShows(showId),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_all, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('Kopier til alle',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _sectionLabel('Skarp', Colors.purple, skarpSelected.length),
          const SizedBox(height: 6),
          _buildMemberCheckList(
            cs: cs,
            members: skarpMembers,
            selected: skarpSelected,
            section: 'skarp',
            showId: showId,
            locked: lockedSkarp,
            canEdit: canEditSkarp,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Bass', Colors.teal, bassSelected.length),
          const SizedBox(height: 6),
          _buildMemberCheckList(
            cs: cs,
            members: bassMembers,
            selected: bassSelected,
            section: 'bass',
            showId: showId,
            locked: lockedBass,
            canEdit: canEditBass,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$title ($count valgt)',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMemberCheckList({
    required ColorScheme cs,
    required List<Map<String, dynamic>> members,
    required Set<String> selected,
    required String section,
    required String showId,
    required bool locked,
    required bool canEdit,
  }) {
    if (members.isEmpty) {
      return Text('Ingen medlemmer.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: members.asMap().entries.map((entry) {
          final i = entry.key;
          final m = entry.value;
          final isLast = i == members.length - 1;
          final uid = m['user_id'] as String;

          IconData statusIcon;
          Color statusColor;
          switch (m['status'] as String?) {
            case 'available':
              statusIcon = Icons.check_circle;
              statusColor = Colors.green;
              break;
            case 'unavailable':
              statusIcon = Icons.cancel;
              statusColor = Colors.red;
              break;
            default:
              statusIcon = Icons.help_outline;
              statusColor = Colors.grey;
          }

          return GestureDetector(
            onTap: (locked || !canEdit)
                ? null
                : () => _toggleLineupMember(uid, section, showId),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: selected.contains(uid),
                      onChanged: (locked || !canEdit)
                          ? null
                          : (_) =>
                              _toggleLineupMember(uid, section, showId),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (m['name'] as String?) ?? 'Ukjent',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _infoSection(ColorScheme cs, List<Widget> children) {
    final filtered = children.whereType<Widget>().toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: filtered,
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AvailButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AvailButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: selected ? color : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MemberAvailability {
  final String userId;
  final String name;
  final String role;
  final String status;

  const _MemberAvailability({
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
  });
}
