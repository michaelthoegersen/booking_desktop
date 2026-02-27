import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';

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
  List<_MemberAvailability> _members = [];

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
              .select('id, name, role')
              .eq('company_id', companyId),
        );
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

  @override
  Widget build(BuildContext context) {
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios,
                    size: 13, color: CssTheme.textMuted),
                SizedBox(width: 2),
                Text(
                  'Gigs',
                  style: TextStyle(
                    color: CssTheme.textMuted,
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
                            ?.copyWith(color: CssTheme.textMuted),
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
                  _infoSection([
                    if (_gig!['meeting_time'] != null)
                      _infoRow('Møtetid', _gig!['meeting_time']),
                    if (_gig!['get_in_time'] != null)
                      _infoRow('Get-in', _gig!['get_in_time']),
                    if (_gig!['rehearsal_time'] != null)
                      _infoRow('Lydprøve', _gig!['rehearsal_time']),
                    if (_gig!['performance_time'] != null)
                      _infoRow('Spilletid', _gig!['performance_time']),
                    if (_gig!['get_out_time'] != null)
                      _infoRow('Get-out', _gig!['get_out_time']),
                    if (_gig!['meeting_notes'] != null &&
                        (_gig!['meeting_notes'] as String).isNotEmpty)
                      _infoRow('Notater', _gig!['meeting_notes']),
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
                    const Text('Ingen crew-medlemmer.',
                        style: TextStyle(color: CssTheme.textMuted))
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: CssTheme.outline),
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
                                  : const Border(
                                      bottom: BorderSide(
                                          color: CssTheme.outline)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: CssTheme.surface2,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoSection(List<Widget> children) {
    final filtered = children.whereType<Widget>().toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CssTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: filtered,
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
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
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: CssTheme.textMuted,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : CssTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : CssTheme.outline,
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
                color: selected ? color : CssTheme.text,
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
