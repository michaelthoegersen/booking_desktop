import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/css_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/dashboard_page.dart';
import '../pages/calendar_page.dart';
import '../pages/new_offer_page.dart';
import '../pages/edit_offer_page.dart';
import '../pages/customers_page.dart';
import '../pages/invoices_page.dart';
import '../pages/economy_page.dart';
import '../pages/issues_page.dart';
import '../pages/settings_page.dart';
import '../pages/routes_admin_page.dart';

// --------------------------------------------------------------------------
// DATA
// --------------------------------------------------------------------------

class _ExtraTab {
  final String id;
  final String route;
  final String title;
  final Widget page;

  _ExtraTab({
    required this.id,
    required this.route,
    required this.title,
    required this.page,
  });
}

const _routeTitles = {
  '/': 'Dashboard',
  '/calendar': 'Calendar',
  '/new': 'New offer',
  '/edit': 'Edit offers',
  '/customers': 'Customers',
  '/invoices': 'Invoices',
  '/economy': 'Economy',
  '/issues': 'Issues',
  '/settings': 'Settings',
  '/routes': 'Route Manager',
};

// --------------------------------------------------------------------------
// APP SHELL
// --------------------------------------------------------------------------

class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({
    super.key,
    required this.child,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final List<_ExtraTab> _extraTabs = [];
  int _activeTabIndex = 0; // 0 = go_router child, 1+ = extra tabs

  // Null = use go_router path for sidebar highlight (tab 0)
  // Non-null = use stored route (extra tab is active)
  String? get _overrideRoute =>
      _activeTabIndex == 0 ? null : _extraTabs[_activeTabIndex - 1].route;

  void _openInNewTab(String route) {
    // If tab 0 already shows this route, switch to tab 0
    final currentPath = GoRouterState.of(context).uri.path;
    if (currentPath == route || currentPath.startsWith('$route/')) {
      setState(() => _activeTabIndex = 0);
      return;
    }

    // If any extra tab already shows this route, switch to it
    for (int i = 0; i < _extraTabs.length; i++) {
      if (_extraTabs[i].route == route) {
        setState(() => _activeTabIndex = i + 1);
        return;
      }
    }

    // Otherwise create new tab
    final tab = _ExtraTab(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      route: route,
      title: _routeTitles[route] ?? route,
      page: _buildPageForRoute(route),
    );

    setState(() {
      _extraTabs.add(tab);
      _activeTabIndex = _extraTabs.length;
    });
  }

  void _closeExtraTab(int extraIndex) {
    setState(() {
      _extraTabs.removeAt(extraIndex);
      // Clamp active index to valid range
      if (_activeTabIndex > _extraTabs.length) {
        _activeTabIndex = _extraTabs.length;
      }
    });
  }

  Widget _buildPageForRoute(String route) {
    switch (route) {
      case '/':
        return DashboardPage();
      case '/calendar':
        return CalendarPage();
      case '/new':
        return NewOfferPage();
      case '/edit':
        return EditOfferPage();
      case '/customers':
        return CustomersPage();
      case '/invoices':
        return InvoicesPage();
      case '/economy':
        return EconomyPage();
      case '/issues':
        return IssuesPage();
      case '/settings':
        return SettingsPage();
      case '/routes':
        return RoutesAdminPage();
      default:
        return Center(child: Text('Unknown route: $route'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Row(
        children: [
          _SideNav(
            onOpenInNewTab: _openInNewTab,
            overrideActiveRoute: _overrideRoute,
          ),

          Expanded(
            child: Column(
              children: [
                const _TopBar(),

                if (_extraTabs.isNotEmpty)
                  _TabBar(
                    activeIndex: _activeTabIndex,
                    extraTabs: _extraTabs,
                    onSelectTab: (i) => setState(() => _activeTabIndex = i),
                    onCloseTab: _closeExtraTab,
                  ),

                Expanded(
                  child: _extraTabs.isEmpty
                      ? widget.child
                      : IndexedStack(
                          index: _activeTabIndex,
                          children: [
                            widget.child,
                            ..._extraTabs.map((t) => t.page),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// TAB BAR
// --------------------------------------------------------------------------

class _TabBar extends StatelessWidget {
  final int activeIndex;
  final List<_ExtraTab> extraTabs;
  final void Function(int) onSelectTab;
  final void Function(int extraIndex) onCloseTab;

  const _TabBar({
    required this.activeIndex,
    required this.extraTabs,
    required this.onSelectTab,
    required this.onCloseTab,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final tab0Title = _routeTitles[currentPath] ?? currentPath;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: const Border(
          bottom: BorderSide(color: Color(0x22000000)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Tab 0 — cannot be closed
            _TabPill(
              title: tab0Title,
              isActive: activeIndex == 0,
              onTap: () => onSelectTab(0),
              onClose: null,
            ),

            // Extra tabs
            for (int i = 0; i < extraTabs.length; i++)
              _TabPill(
                title: extraTabs[i].title,
                isActive: activeIndex == i + 1,
                onTap: () => onSelectTab(i + 1),
                onClose: () => onCloseTab(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TabPill({
    required this.title,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          boxShadow: isActive
              ? const [BoxShadow(blurRadius: 4, color: Colors.black12)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// TOP BAR
// --------------------------------------------------------------------------
class _TopBar extends StatefulWidget {
  const _TopBar();

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  String? fullName;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;

    if (user == null) return;

    try {
      final res = await sb
          .from('profiles') // 👈 endre hvis tabellen heter noe annet
          .select('name')
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      setState(() {
        fullName = res['name'];
        loading = false;
      });

    } catch (e) {
      debugPrint("User load failed: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? "Unknown user";

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
          // ---------------- Title ----------------
          RichText(
            text: const TextSpan(
              children: [
                // Hovednavn
                TextSpan(
                  text: "TourFlow",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),

                // Separator
                TextSpan(
                  text: "  —  ",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),

                // Undertittel
                TextSpan(
                  text: "booking system for nightliners",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          const Spacer(),

          // ---------------- USER MENU ----------------
          PopupMenuButton<String>(
            tooltip: "Account",

            onSelected: (value) async {
              if (value == "logout") {
                await Supabase.instance.client.auth.signOut();

                if (context.mounted) {
                  context.go('/login');
                }
              }
            },

            itemBuilder: (context) => [
              // 👤 Bruker-info
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Signed in as",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const PopupMenuDivider(),

              // 🚪 Logout
              const PopupMenuItem(
                value: "logout",
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text("Log out"),
                  ],
                ),
              ),
            ],

            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
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
  loading
      ? "..."
      : (fullName ?? email.split('@').first),
  style: const TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
  ),
),

    const SizedBox(width: 8),

    const Icon(
      Icons.keyboard_arrow_down,
      color: Colors.white70,
    ),
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
class _SideNav extends StatefulWidget {
  final void Function(String route)? onOpenInNewTab;
  final String? overrideActiveRoute;

  const _SideNav({this.onOpenInNewTab, this.overrideActiveRoute});

  @override
  State<_SideNav> createState() => _SideNavState();
}

class _SideNavState extends State<_SideNav> {
  final _supabase = Supabase.instance.client;
  int _unseenCount = 0;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadUnseenCount();
    _subscribeRealtime();
    // Poll every 15 seconds as fallback if realtime doesn't fire
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadUnseenCount());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnseenCount() async {
    try {
      final res = await _supabase
          .from('issues')
          .select('id')
          .or('seen_by_admin.is.null,seen_by_admin.eq.false');
      if (mounted) setState(() => _unseenCount = res.length);
    } catch (e) {
      debugPrint('Badge count error: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('issues-badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'issues',
          callback: (_) => _loadUnseenCount(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: CssTheme.surface,
        border: Border(
          right: BorderSide(color: CssTheme.outline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: Center(
                child: Image.asset(
                  "assets/pdf/logos/TourFlowLogo.png",
                  height: 150,
                  fit: BoxFit.contain,
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

            // --------------------------------------------------
            // NAV ITEMS
            // --------------------------------------------------
            _NavItem(
              icon: Icons.dashboard_rounded,
              label: "Dashboard",
              route: "/",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.calendar_month,
              label: "Calendar",
              route: "/calendar",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.add_circle_outline,
              label: "New offer",
              route: "/new",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.edit_note,
              label: "Edit offers",
              route: "/edit",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.apartment_rounded,
              label: "Customers",
              route: "/customers",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.receipt_long_rounded,
              label: "Invoices",
              route: "/invoices",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.bar_chart_rounded,
              label: "Economy",
              route: "/economy",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            _NavItem(
              icon: Icons.report_problem_rounded,
              label: "Issues",
              route: "/issues",
              badge: _unseenCount,
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
            ),

            const Spacer(),

            _NavItem(
              icon: Icons.settings,
              label: "Settings",
              route: "/settings",
              onOpenInNewTab: widget.onOpenInNewTab,
              overrideActiveRoute: widget.overrideActiveRoute,
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
class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final int badge;
  final void Function(String route)? onOpenInNewTab;
  final String? overrideActiveRoute;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    this.badge = 0,
    this.onOpenInNewTab,
    this.overrideActiveRoute,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  Offset _tapPosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final currentPath =
        widget.overrideActiveRoute ?? GoRouterState.of(context).uri.path;

    final selected =
        currentPath == widget.route || currentPath.startsWith('${widget.route}/');

    return GestureDetector(
      onTap: () => context.go(widget.route),
      onSecondaryTapDown: (details) {
        _tapPosition = details.globalPosition;
      },
      onSecondaryTap: () {
        if (widget.onOpenInNewTab == null) return;
        final overlay =
            Overlay.of(context).context.findRenderObject()! as RenderBox;
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            _tapPosition.dx,
            _tapPosition.dy,
            overlay.size.width - _tapPosition.dx,
            overlay.size.height - _tapPosition.dy,
          ),
          items: const [
            PopupMenuItem(
              value: 'new_tab',
              child: Row(
                children: [
                  Icon(Icons.tab, size: 18),
                  SizedBox(width: 8),
                  Text('Åpne i ny fane'),
                ],
              ),
            ),
          ],
        ).then((v) {
          if (v == 'new_tab') widget.onOpenInNewTab?.call(widget.route);
        });
      },

      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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
              widget.icon,
              color: selected ? Colors.white : Colors.black87,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : Colors.black87,
                ),
              ),
            ),

            if (widget.badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.badge > 99 ? '99+' : '${widget.badge}',
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
