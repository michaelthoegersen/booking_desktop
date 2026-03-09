import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/css_theme.dart';
import '../ui/web_svg_image.dart';
import '../state/active_company.dart';

class ArtistLoginPage extends StatefulWidget {
  const ArtistLoginPage({super.key});

  @override
  State<ArtistLoginPage> createState() => _ArtistLoginPageState();
}

class _ArtistLoginPageState extends State<ArtistLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  final SupabaseClient _sb = Supabase.instance.client;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _sb.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      // Check that user is NOT a CSS user
      await activeCompanyNotifier.load();
      final mode = activeCompanyNotifier.value?.appMode ?? 'css';
      if (mode == 'css') {
        await _sb.auth.signOut();
        setState(() => _error = 'This account belongs to Logistics. Please use the Logistics portal.');
        return;
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Login failed");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: CssTheme.bg,

    body: Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CssTheme.outline),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ---------------- LOGO ----------------
const WebSvgImage(
  svgAsset: 'LogoTourFlowArtist.svg',
  pngFallback: 'assets/LogoTourFlowArtist.png',
  width: 250,
  height: 130,
),

const SizedBox(height: 16),

// ---------------- TITLE ----------------
const Text(
  "TourFlow Artist",
  style: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
  ),
),

const SizedBox(height: 4),

const Text(
  "Your stage. Your schedule. Your flow.",
  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.black54,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.3,
  ),
),
const SizedBox(height: 20),


            // ---------------- EMAIL ----------------
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,

              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),

            const SizedBox(height: 14),

            // ---------------- PASSWORD ----------------
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _loading ? null : _login(),

              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),

            const SizedBox(height: 18),

            // ---------------- ERROR ----------------
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),

                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            if (_error != null) const SizedBox(height: 14),

            // ---------------- LOGIN BUTTON ----------------
            SizedBox(
              width: double.infinity,
              height: 52,

              child: FilledButton(
                onPressed: _loading ? null : _login,

                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Sign in",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ---------------- BACK ----------------
            TextButton.icon(
              onPressed: () => context.go('/portal'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
      ),
    ),
  );
}
}
