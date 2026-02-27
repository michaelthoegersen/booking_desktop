import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/mgmt/mgmt_settings_page.dart' show companyFlagsNotifier;
import '../ui/css_theme.dart';

/// Notifier so the sidebar badge updates immediately after marking messages read.
final mgmtUnreadNotifier = ValueNotifier<int>(0);

// --------------------------------------------------------------------------
// MANAGEMENT SHELL
// --------------------------------------------------------------------------

class MgmtShell extends StatelessWidget {
  final Widget child;

  const MgmtShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Row(
        children: [
          const _MgmtSideNav(),
          Expanded(
            child: Column(
              children: [
                const _MgmtTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// TOP BAR
// --------------------------------------------------------------------------

class _MgmtTopBar extends StatefulWidget {
  const _MgmtTopBar();

  @override
  State<_MgmtTopBar> createState() => _MgmtTopBarState();
}

class _MgmtTopBarState extends State<_MgmtTopBar> {
  String? _userName;
  String? _companyName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await sb
          .from('profiles')
          .select('name, company_id')
          .eq('id', user.id)
          .maybeSingle();

      String? companyName;
      if (profile?['company_id'] != null) {
        final company = await sb
            .from('companies')
            .select('name')
            .eq('id', profile!['company_id'])
            .maybeSingle();
        companyName = company?['name'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _userName = profile?['name'] as String?;
        _companyName = companyName;
      });
    } catch (e) {
      debugPrint('MgmtTopBar load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: CssTheme.header,
        border: Border(
          bottom: BorderSide(color: Color(0x33000000)),
        ),
      ),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(
                  text: "TourFlow",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const TextSpan(
                  text: "  —  ",
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                TextSpan(
                  text: _companyName != null
                      ? 'Management · $_companyName'
                      : 'Management',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: "Account",
            onSelected: (value) async {
              if (value == 'logout') {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Signed in as",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Log out'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _userName ?? email.split('@').first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// SIDE NAV
// --------------------------------------------------------------------------

class _MgmtSideNav extends StatefulWidget {
  const _MgmtSideNav();

  @override
  State<_MgmtSideNav> createState() => _MgmtSideNavState();
}

class _MgmtSideNavState extends State<_MgmtSideNav> {
  final _sb = Supabase.instance.client;
  bool _showTours = true;
  int _unreadMessages = 0;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadFlags();
    _loadUnreadMessages();
    companyFlagsNotifier.addListener(_onFlagsChanged);
    mgmtUnreadNotifier.addListener(_loadUnreadMessages);
    _channel = _sb
        .channel('mgmt-sidenav-badges')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'gig_messages',
          callback: (_) => _loadUnreadMessages(),
        )
        .subscribe();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadUnreadMessages();
    });
  }

  @override
  void dispose() {
    companyFlagsNotifier.removeListener(_onFlagsChanged);
    mgmtUnreadNotifier.removeListener(_loadUnreadMessages);
    _channel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadMessages() async {
    try {
      final res = await _sb
          .from('gig_messages')
          .select('id')
          .eq('is_admin', false)
          .or('read_by_admin.is.null,read_by_admin.eq.false');
      if (mounted) setState(() => _unreadMessages = (res as List).length);
    } catch (e) {
      debugPrint('Mgmt chat badge error: $e');
    }
  }

  void _onFlagsChanged() {
    if (!mounted) return;
    setState(() {
      _showTours = companyFlagsNotifier.value['show_tours'] ?? true;
    });
  }

  Future<void> _loadFlags() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final profile = await sb
          .from('profiles')
          .select('company_id')
          .eq('id', uid)
          .maybeSingle();
      final companyId = profile?['company_id'] as String?;
      if (companyId == null) return;
      final company = await sb
          .from('companies')
          .select('show_tours')
          .eq('id', companyId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _showTours = company?['show_tours'] != false;
        });
      }
    } catch (e) {
      debugPrint('SideNav flags error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: CssTheme.surface,
        border: Border(right: BorderSide(color: CssTheme.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: Center(
                child: Image(
                  image: const ResizeImage(
                    AssetImage("assets/pdf/logos/TourFlowLogoComplete.png"),
                    width: 900,
                  ),
                  height: 150,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) {
                    return const Text(
                      "TourFlow",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    );
                  },
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _MgmtNavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      route: '/m',
                    ),
                    if (_showTours)
                      _MgmtNavItem(
                        icon: Icons.map_rounded,
                        label: 'Tours',
                        route: '/m/tours',
                      ),
                    _MgmtNavItem(
                      icon: Icons.music_note_rounded,
                      label: 'Gigs',
                      route: '/m/gigs',
                    ),
                    _MgmtNavItem(
                      icon: Icons.people_rounded,
                      label: 'People',
                      route: '/m/people',
                    ),
                    _MgmtNavItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Messages',
                      route: '/m/messages',
                      badge: _unreadMessages,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            _MgmtNavItem(
              icon: Icons.settings,
              label: 'Settings',
              route: '/m/settings',
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// NAV ITEM
// --------------------------------------------------------------------------

class _MgmtNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final int badge;

  const _MgmtNavItem({
    required this.icon,
    required this.label,
    required this.route,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    // Exact match for /m (dashboard), prefix match for others
    final selected = route == '/m'
        ? currentPath == '/m'
        : currentPath.startsWith(route);

    return GestureDetector(
      onTap: () => context.go(route),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.black : CssTheme.outline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.red : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
