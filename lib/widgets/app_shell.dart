import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/css_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Row(
        children: [
          const _SideNav(),

          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// TOP BAR
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// SIDE NAV
// ------------------------------------------------------------
class _SideNav extends StatelessWidget {
  const _SideNav();

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
            // --------------------------------------------------
// --------------------------------------------------
// LOGO (REN + STØRRE)
// --------------------------------------------------
Padding(
  padding: const EdgeInsets.only(bottom: 20, top: 10),
  child: Center(
    child: Image.asset(
      "assets/pdf/logos/TourFlowLogo.png",

      height: 150, // 👈 større logo
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
            const _NavItem(
              icon: Icons.dashboard_rounded,
              label: "Dashboard",
              route: "/",
            ),

            const _NavItem(
              icon: Icons.calendar_month,
              label: "Calendar",
              route: "/calendar",
            ),

            const _NavItem(
              icon: Icons.add_circle_outline,
              label: "New offer",
              route: "/new",
            ),

            const _NavItem(
              icon: Icons.edit_note,
              label: "Edit offers",
              route: "/edit",
            ),

            const _NavItem(
              icon: Icons.apartment_rounded,
              label: "Customers",
              route: "/customers",
            ),

            const _NavItem(
              icon: Icons.receipt_long_rounded,
              label: "Invoices",
              route: "/invoices",
            ),

            const _NavItem(
              icon: Icons.report_problem_rounded,
              label: "Issues",
              route: "/issues",
            ),

            const Spacer(),

            const _NavItem(
              icon: Icons.settings,
              label: "Settings",
              route: "/settings",
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// NAV ITEM
// ------------------------------------------------------------
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;

    final selected =
        currentPath == route || currentPath.startsWith("$route/");

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(route),

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
              icon,
              color: selected ? Colors.white : Colors.black87,
            ),

            const SizedBox(width: 10),

            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}