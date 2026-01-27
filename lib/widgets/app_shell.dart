import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/css_theme.dart';

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
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
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
          Text(
            "Booking System",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
          ),

          const SizedBox(width: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              "Desktop",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),

          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(
              children: [
                Icon(Icons.person, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text("Signed in", style: TextStyle(color: Colors.white)),
                SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down, color: Colors.white70),
              ],
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
            // LOGO
            // --------------------------------------------------
            Container(
              height: 90,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                border: Border.all(color: CssTheme.outline),
              ),
              child: Image.asset(
                "assets/pdf/logos/TourFlowLogo.png",
                fit: BoxFit.contain,

                errorBuilder: (context, error, stack) {
                  return const Center(
                    child: Text(
                      "LOGO",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

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