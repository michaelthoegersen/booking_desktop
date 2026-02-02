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

    if (a.isEmpty || b.isEmpty) return null;

    const selectFields = '''
      id,
      from_place,
      to_place,
      distance_total_km,
      ferry_price,
      toll_nightliner,
      extra,
      km_dk,
      km_de,
      km_be,
      km_pl,
      km_au,
      km_hr,
      km_si,
      km_other
    ''';

    try {
      // EXACT
      final exact = await _client
          .from('routes_all')
          .select(selectFields)
          .eq('from_place', a)
          .eq('to_place', b)
          .limit(1);

      if (exact is List && exact.isNotEmpty) {
        final row = Map<String, dynamic>.from(exact.first);

        if (_hasValidKm(row)) return row;
      }

      // REVERSE
      final reverse = await _client
          .from('routes_all')
          .select(selectFields)
          .eq('from_place', b)
          .eq('to_place', a)
          .limit(1);

      if (reverse is List && reverse.isNotEmpty) {
        final row = Map<String, dynamic>.from(reverse.first);

        if (_hasValidKm(row)) return row;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // SEARCH
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

      return list.length > limit
          ? list.take(limit).toList()
          : list;
    } catch (_) {
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

    return (res as List).cast<Map<String, dynamic>>();
  }

  // ------------------------------------------------------------
  // ADMIN: CREATE
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
  // ADMIN: UPDATE
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
  // ADMIN: DELETE
  // ------------------------------------------------------------
  Future<void> deleteRoute(String id) async {
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
    final existing = await findRoute(from: from, to: to);

    if (existing != null) return existing;

    final insertData = {
      'from_place': from.trim(),
      'to_place': to.trim(),
      'distance_total_km': totalKm,

      'km_dk': countryKm['DK'] ?? 0,
      'km_de': countryKm['DE'] ?? 0,
      'km_be': countryKm['BE'] ?? 0,
      'km_pl': countryKm['PL'] ?? 0,
      'km_au': countryKm['AT'] ?? 0,
      'km_hr': countryKm['HR'] ?? 0,
      'km_si': countryKm['SI'] ?? 0,
      'km_other': countryKm['OTHER'] ?? 0,

      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('routes_all').insert(insertData);

    return (await findRoute(from: from, to: to))!;
  }
}