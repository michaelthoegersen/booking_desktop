import 'package:supabase_flutter/supabase_flutter.dart';

class RoutesService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Finner route i routes_all med eksakt match.
  /// Prøver også reverse (to->from) dersom ikke funnet.
  Future<Map<String, dynamic>?> findRoute({
    required String from,
    required String to,
  }) async {
    final a = from.trim();
    final b = to.trim();
    if (a.isEmpty || b.isEmpty) return null;

    final exact = await _client
        .from('routes_all')
        .select()
        .eq('from_place', a)
        .eq('to_place', b)
        .maybeSingle();

    if (exact != null) return exact;

    final reverse = await _client
        .from('routes_all')
        .select()
        .eq('from_place', b)
        .eq('to_place', a)
        .maybeSingle();

    return reverse;
  }
}