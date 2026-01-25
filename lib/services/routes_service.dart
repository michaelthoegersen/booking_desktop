import 'package:supabase_flutter/supabase_flutter.dart';

class RoutesService {
  final SupabaseClient _client = Supabase.instance.client;

  // ------------------------------------------------------------
  // Utils
  // ------------------------------------------------------------
  String _norm(String s) => s.trim();

  // ------------------------------------------------------------
  // ✅ Finn route (IKKE maybeSingle!)
  // Brukes av kalkulator / new offer
  // ------------------------------------------------------------
  Future<Map<String, dynamic>?> findRoute({
    required String from,
    required String to,
  }) async {
    final a = _norm(from);
    final b = _norm(to);
    if (a.isEmpty || b.isEmpty) return null;

    try {
      // 1️⃣ Eksakt match
      final exact = await _client
          .from('routes_all')
          .select(
            'distance_total_km, ferry_price, toll_nightliner, extra',
          )
          .eq('from_place', a)
          .eq('to_place', b)
          .limit(1);

      if (exact is List && exact.isNotEmpty) {
        return Map<String, dynamic>.from(exact.first);
      }

      // 2️⃣ Reverse match
      final reverse = await _client
          .from('routes_all')
          .select(
            'distance_total_km, ferry_price, toll_nightliner, extra',
          )
          .eq('from_place', b)
          .eq('to_place', a)
          .limit(1);

      if (reverse is List && reverse.isNotEmpty) {
        return Map<String, dynamic>.from(reverse.first);
      }

      return null;
    } catch (e) {
      // ⚠️ viktig: ikke la exceptions drepe kalkyle
      return null;
    }
  }

  // ------------------------------------------------------------
  // ✅ Autocomplete: hent steder fra routes_all
  // Brukes i NewOfferPage
  // ------------------------------------------------------------
  Future<List<String>> searchPlaces(
    String query, {
    int limit = 12,
  }) async {
    final q = _norm(query);
    if (q.length < 2) return [];

    try {
      final fromRes = await _client
          .from('routes_all')
          .select('from_place')
          .ilike('from_place', '%$q%')
          .order('from_place')
          .limit(limit * 2);

      final toRes = await _client
          .from('routes_all')
          .select('to_place')
          .ilike('to_place', '%$q%')
          .order('to_place')
          .limit(limit * 2);

      final places = <String>{};

      if (fromRes is List) {
        for (final row in fromRes) {
          final v = row['from_place']?.toString().trim();
          if (v != null && v.isNotEmpty) places.add(v);
        }
      }

      if (toRes is List) {
        for (final row in toRes) {
          final v = row['to_place']?.toString().trim();
          if (v != null && v.isNotEmpty) places.add(v);
        }
      }

      final list = places.toList()..sort();
      return list.length > limit ? list.take(limit).toList() : list;
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // 🔧 ADMIN / CRUD
  // Brukes KUN av RoutesAdminPage
  // ============================================================

  // ------------------------------------------------------------
  // READ ALL
  // ------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final res = await _client
        .from('routes_all')
        .select()
        .order('from_place');

    return (res as List).cast<Map<String, dynamic>>();
  }

  // ------------------------------------------------------------
  // READ ONE
  // ------------------------------------------------------------
  Future<Map<String, dynamic>?> getRouteById(String id) async {
    final res = await _client
        .from('routes_all')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  // ------------------------------------------------------------
  // CREATE
  // ------------------------------------------------------------
  Future<void> createRoute({
    required String from,
    required String to,
    required double km,
    double ferry = 0,
    double toll = 0,
    String extra = '',
  }) async {
    await _client.from('routes_all').insert({
      'from_place': from.trim(),
      'to_place': to.trim(),
      'distance_total_km': km,
      'ferry_price': ferry,
      'toll_nightliner': toll,
      'extra': extra,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ------------------------------------------------------------
  // UPDATE
  // ------------------------------------------------------------
  Future<void> updateRoute({
    required String id,
    required String from,
    required String to,
    required double km,
    double ferry = 0,
    double toll = 0,
    String extra = '',
  }) async {
    await _client
        .from('routes_all')
        .update({
          'from_place': from.trim(),
          'to_place': to.trim(),
          'distance_total_km': km,
          'ferry_price': ferry,
          'toll_nightliner': toll,
          'extra': extra,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // ------------------------------------------------------------
  // DELETE
  // ------------------------------------------------------------
  Future<void> deleteRoute(String id) async {
    await _client.from('routes_all').delete().eq('id', id);
  }
}