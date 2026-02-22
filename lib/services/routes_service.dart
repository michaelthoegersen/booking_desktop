import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoutesService {
  final SupabaseClient _client = Supabase.instance.client;

  // ------------------------------------------------------------
  // Utils
  // ------------------------------------------------------------
  String _norm(String s) => s.trim();

  bool _hasValidKm(Map row) {
    final v = row['distance_total_km'];
    return v != null && v is num && v > 0;
  }

  // ------------------------------------------------------------
  // FIND ROUTE (only if valid km)
  // ------------------------------------------------------------
  Future<Map<String, dynamic>?> findRoute({
    required String from,
    required String to,
  }) async {
    final a = _norm(from);
    final b = _norm(to);

    if (a.isEmpty || b.isEmpty) {
      debugPrint('[ROUTE] ❌ Empty from/to');
      return null;
    }

    const selectFields = '''
      id,
      from_place,
      to_place,
      distance_total_km,
      ferry_name,
      base_price:ferry_price,
      extra,
      no_ddrive,
      km_se,
      km_dk,
      km_de,
      km_be,
      km_pl,
      km_at,
      km_hr,
      km_si,
      km_other
    ''';

    debugPrint('[ROUTE] 🔍 Lookup: "$a" → "$b"');

    try {
      // ================= EXACT =================
      final exact = await _client
          .from('routes_all')
          .select(selectFields)
          .eq('from_place', a)
          .eq('to_place', b)
          .limit(1);

      if (exact is List && exact.isNotEmpty) {
        final row = Map<String, dynamic>.from(exact.first);

        debugPrint(
          '[ROUTE] ✅ EXACT HIT $a → $b | '
          'km=${row['distance_total_km']} '
          'ferry_name="${row['ferry_name']}" '
          'ferry_price=${row['ferry_price']}',
        );

        if (_hasValidKm(row)) return row;

        debugPrint('[ROUTE] ⚠️ EXACT found but invalid km');
      }

      debugPrint('[ROUTE] ❌ NO ROUTE FOUND: $a → $b');
      return null;

    } catch (e, st) {
      debugPrint('[ROUTE] 💥 LOOKUP FAILED: $e');
      debugPrint(st.toString());
      return null;
    }
  }

  // ------------------------------------------------------------
  // SEARCH (autocomplete)
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

      debugPrint('[ROUTE] 🔎 searchPlaces("$q") → ${list.length} results');

      return list.length > limit
          ? list.take(limit).toList()
          : list;

    } catch (e) {
      debugPrint('[ROUTE] ❌ searchPlaces failed: $e');
      return [];
    }
  }

  // ------------------------------------------------------------
  // ADMIN: GET ALL
  // ------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final res = await _client
        .from('routes_all')
        .select()
        .order('from_place');

    debugPrint('[ROUTE] 📦 getAllRoutes → ${(res as List).length} rows');
    return (res).cast<Map<String, dynamic>>();
  }

  // ------------------------------------------------------------
  // ADMIN: CREATE
  // ------------------------------------------------------------
  Future<void> createRoute({
    required String from,
    required String to,
    required double km,
    double ferry = 0,
    String extra = '',
  }) async {
    debugPrint(
      '[ROUTE] ➕ CREATE $from → $to | km=$km ferry=$ferry',
    );

    await _client.from('routes_all').insert({
      'from_place': from.trim(),
      'to_place': to.trim(),
      'distance_total_km': km,
      'ferry_price': ferry,
      'extra': extra,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ------------------------------------------------------------
  // ADMIN: UPDATE
  // ------------------------------------------------------------
  Future<void> updateRoute({
    required String id,
    required String from,
    required String to,
    required double km,
    double ferry = 0,
    String extra = '',
  }) async {
    debugPrint(
      '[ROUTE] ✏️ UPDATE id=$id | $from → $to | km=$km ferry=$ferry',
    );

    await _client
        .from('routes_all')
        .update({
          'from_place': from.trim(),
          'to_place': to.trim(),
          'distance_total_km': km,
          'ferry_price': ferry,
          'extra': extra,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // ------------------------------------------------------------
  // ADMIN: DELETE
  // ------------------------------------------------------------
  Future<void> deleteRoute(String id) async {
    debugPrint('[ROUTE] 🗑️ DELETE id=$id');
    await _client.from('routes_all').delete().eq('id', id);
  }

  // ------------------------------------------------------------
  // AUTO CACHE
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> findOrCreateRoute({
    required String from,
    required String to,
    required double totalKm,
    required Map<String, double> countryKm,
  }) async {
    debugPrint('[ROUTE] 🔁 findOrCreate $from → $to');

    final existing = await findRoute(from: from, to: to);
    if (existing != null) {
      debugPrint('[ROUTE] ♻️ Using existing route');
      return existing;
    }

    debugPrint('[ROUTE] 🆕 Auto-create route');

    final insertData = {
      'from_place': from.trim(),
      'to_place': to.trim(),
      'distance_total_km': totalKm,
      'km_dk': countryKm['DK'] ?? 0,
      'km_de': countryKm['DE'] ?? 0,
      'km_be': countryKm['BE'] ?? 0,
      'km_pl': countryKm['PL'] ?? 0,
      'km_at': countryKm['AT'] ?? 0,
      'km_hr': countryKm['HR'] ?? 0,
      'km_si': countryKm['SI'] ?? 0,
      'km_other': countryKm['OTHER'] ?? 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('routes_all').insert(insertData);

    final created = await findRoute(from: from, to: to);
    debugPrint('[ROUTE] ✅ Auto-created route confirmed');

    return created!;
  }
}