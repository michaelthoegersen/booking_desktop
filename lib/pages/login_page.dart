import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/css_theme.dart';

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
    final res = await _sb.auth.signInWithPassword(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    final session = res.session;
    final user = res.user;

    debugPrint("LOGIN USER: $user");
    debugPrint("LOGIN SESSION: $session");

    if (session == null || user == null) {
      throw "No session after login";
    }

    if (!mounted) return;

    // 🔥 Viktig: Gå videre til app
    Navigator.of(context).pushReplacementNamed("/");
  } on AuthException catch (e) {
    setState(() => _error = e.message);
  } catch (e) {
    debugPrint("LOGIN ERROR: $e");

    setState(() => _error = "Login failed");
  } finally {
    if (mounted) {
      setState(() => _loading = false);
    }
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
SizedBox(
  height: 130, // 👈 større logo
  child: Image.asset(
    "assets/pdf/logos/TourFlowLogo.png",
    fit: BoxFit.contain,

    errorBuilder: (_, __, ___) {
      return const Text(
        "TourFlow",
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      );
    },
  ),
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
          ],
        ),
      ),
    ),
  );
}
}