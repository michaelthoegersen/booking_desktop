import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  /// Henter alle ruter fra routes_all (din master-tabell)
  Future<List<Map<String, dynamic>>> getRoutesAll() async {
    final res = await client
        .from('routes_all')
        .select()
        .order('from_place', ascending: true);

    return List<Map<String, dynamic>>.from(res);
  }

  /// søk: f.eks Oslo → Berlin
  Future<List<Map<String, dynamic>>> searchRoutes(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final res = await client
        .from('routes_all')
        .select()
        .or('from_place.ilike.%$q%,to_place.ilike.%$q%')
        .limit(50);

    return List<Map<String, dynamic>>.from(res);
  }
}