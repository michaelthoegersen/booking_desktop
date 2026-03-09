import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../ui/css_theme.dart';
import '../ui/web_svg_image.dart';

class PortalSelectorPage extends StatelessWidget {
  const PortalSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CssTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Main logo ──
              const WebSvgImage(
                svgAsset: 'TourFlowLogoFront.svg',
                pngFallback: 'assets/TourFlowLogoFront.png',
                width: 300,
                height: 200,
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose your portal',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 40),

              // ── 3 cards side by side ──
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PortalCard(
                        logo: const _ArtistLogo(),
                        title: 'Artist',
                        subtitle: 'Your stage.\nYour schedule.\nYour flow.',
                        onTap: () => context.go('/login-artist'),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _PortalCard(
                        logo: const _ManagementLogo(),
                        title: 'Management',
                        subtitle: 'Tours, bookings\n& team\nmanagement.',
                        dimmed: true,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kommer snart')),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _PortalCard(
                        logo: const _LogisticsLogo(),
                        title: 'Logistics',
                        subtitle: 'Booking system\nfor nightliners\n& transport.',
                        onTap: () => context.go('/login'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN LOGO
// ─────────────────────────────────────────────────────────────────────────────

class _MainLogo extends StatelessWidget {
  const _MainLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cirkel med gradient + ikon
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF8F00), // warm amber
                Color(0xFFE65100), // deep orange
                Color(0xFF1A237E), // dark navy
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.headphones, size: 56, color: Colors.white),
              Positioned(
                bottom: 22,
                child: Icon(Icons.music_note, size: 22, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'TourFlow',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose your portal',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD LOGOS
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistLogo extends StatelessWidget {
  const _ArtistLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B35), Color(0xFFE91E63)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E63).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.mic, size: 30, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'TourFlow',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: 0.5,
          ),
        ),
        const Text(
          'ARTIST',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE91E63),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _ManagementLogo extends StatelessWidget {
  const _ManagementLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF448AFF).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.equalizer, size: 30, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'TourFlow',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: 0.5,
          ),
        ),
        const Text(
          'MANAGEMENT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF448AFF),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _LogisticsLogo extends StatelessWidget {
  const _LogisticsLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00C853), Color(0xFF00897B)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00C853).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.directions_bus, size: 30, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'TourFlow',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: 0.5,
          ),
        ),
        const Text(
          'LOGISTICS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF00897B),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PORTAL CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PortalCard extends StatefulWidget {
  final Widget logo;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dimmed;

  const _PortalCard({
    required this.logo,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dimmed = false,
  });

  @override
  State<_PortalCard> createState() => _PortalCardState();
}

class _PortalCardState extends State<_PortalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final opacity = widget.dimmed ? 0.5 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translate(0.0, _hovered && !widget.dimmed ? -6.0 : 0.0),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered && !widget.dimmed
                  ? Colors.black38
                  : CssTheme.outline,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered && !widget.dimmed
                    ? Colors.black26
                    : Colors.black12,
                blurRadius: _hovered && !widget.dimmed ? 24 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Opacity(
            opacity: opacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.logo,
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                if (widget.dimmed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Coming soon',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
