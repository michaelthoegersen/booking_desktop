import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/app_env.dart';

/// Standalone client used by the calendar/offer services.
///
/// Reads through [AppEnv] so it honours `--dart-define` as well as the bundled
/// `.env` — reading `dotenv.env` directly threw on release builds, where the
/// file was never loaded.
final supabaseDesktop = SupabaseClient(
  AppEnv.supabaseUrl,
  AppEnv.supabaseAnonKey,
);
