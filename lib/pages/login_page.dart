import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/css_theme.dart';
import '../ui/web_svg_image.dart';
import '../state/active_company.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  final SupabaseClient _sb = Supabase.instance.client;

  /// Members cannot reset their own password — the app does not use Supabase
  /// Auth's email. Instead the request goes to the company's admins, who set a
  /// new password from Innstillinger → Medlemmer.
  Future<void> _requestPasswordReset() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Glemt passord'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skriv inn e-postadressen din, så gir vi beskjed til '
              'administrator. Du får et nytt passord av dem.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-post',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Send forespørsel'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (email == null || email.isEmpty || !mounted) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'request-password-reset',
        body: {'email': email},
      );
    } catch (e) {
      debugPrint('Password reset request error: $e');
    }
    // Same message either way — whether the address exists is not something
    // an anonymous visitor should be able to find out.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Administrator har fått beskjed. Du blir kontaktet med nytt '
              'passord.'),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

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

      // Check that user IS a CSS user
      await activeCompanyNotifier.load();
      final mode = activeCompanyNotifier.value?.appMode ?? 'css';
      if (mode != 'css') {
        await _sb.auth.signOut();
        setState(() => _error = 'This account belongs to Artist. Please use the Artist portal.');
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
  svgAsset: 'pdf/logos/TourFlowLogo.svg',
  width: 300,
  height: 130,
),

const SizedBox(height: 16),

// ---------------- TITLE ----------------
const Text(
  "TourFlow",
  style: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
  ),
),

const SizedBox(height: 4),

const Text(
  "Booking system for nightliners",
  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.black54,
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
            const SizedBox(height: 8),

            // ---------------- FORGOT PASSWORD ----------------
            TextButton(
              onPressed: _loading ? null : _requestPasswordReset,
              child: const Text('Glemt passord?'),
            ),
            const SizedBox(height: 12),

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