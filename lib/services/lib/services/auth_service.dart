import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  // Nåværende bruker
  static User? get currentUser => _client.auth.currentUser;

  // Stream: lytter på login/logout
  static Stream<AuthState> get authState =>
      _client.auth.onAuthStateChange;

  // Logg inn
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Registrer ny bruker
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  // Logg ut
  static Future<void> signOut() {
    return _client.auth.signOut();
  }
}