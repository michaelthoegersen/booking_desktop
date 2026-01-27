import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseDesktop = SupabaseClient(
  dotenv.env['SUPABASE_URL']!,
  dotenv.env['SUPABASE_ANON_KEY']!,
);

final supabaseDrivers = SupabaseClient(
  dotenv.env['SUPABASE_URL_DRIVERS']!,
  dotenv.env['SUPABASE_KEY_DRIVERS']!,
);