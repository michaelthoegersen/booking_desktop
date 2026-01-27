import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      await _sb.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Login failed");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          elevation: 4,
          child: SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Login",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Email",
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password",
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text("Login"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}