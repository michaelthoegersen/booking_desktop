import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/active_company.dart';
import '../ui/css_theme.dart';

// --------------------------------------------------------------------------
// CREW SHELL — enkel layout for crew-brukere (mobil/desktop)
// --------------------------------------------------------------------------

class CrewShell extends StatelessWidget {
  final Widget child;

  const CrewShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Row(
        children: [
          const _CrewSideNav(),
          Expanded(
            child: Column(
              children: [
                const _CrewTopBar(),
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

class _CrewTopBar extends StatefulWidget {
  const _CrewTopBar();

  @override
  State<_CrewTopBar> createState() => _CrewTopBarState();
}

class _CrewTopBarState extends State<_CrewTopBar> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await sb
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _userName = profile?['name'] as String?;
      });
    } catch (e) {
      debugPrint('CrewTopBar load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final companyName = activeCompanyNotifier.value?.name ?? '';

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
                  text: companyName.isNotEmpty ? companyName : 'Crew',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white70),
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

class _CrewSideNav extends StatelessWidget {
  const _CrewSideNav();

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
                    width: 500,
                  ),
                  height: 110,
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
            _CrewNavItem(
              icon: Icons.music_note_rounded,
              label: 'Gigs',
              route: '/c',
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

class _CrewNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;

  const _CrewNavItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selected = route == '/c'
        ? currentPath == '/c'
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
          ],
        ),
      ),
    );
  }
}
