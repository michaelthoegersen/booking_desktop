import 'package:supabase_flutter/supabase_flutter.dart';

class RoutesService {
  final SupabaseClient _client = Supabase.instance.client;

  // ------------------------------------------------------------
  // Utils
  // ------------------------------------------------------------
  String _norm(String s) => s.trim();

  // ------------------------------------------------------------
  // ✅ Finn route (IKKE maybeSingle!)
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
      // ⚠️ viktig: ikke la exceptions drepe hele kalkylen
      return null;
    }
  }

  // ------------------------------------------------------------
  // ✅ Autocomplete: hent steder fra routes_all
  // ------------------------------------------------------------
  Future<List<String>> searchPlaces(
    String query, {
    int limit = 12,
  }) async {
    final q = _norm(query);
    if (q.length < 2) return [];

    try {
      // hent litt flere enn limit – Set filtrerer senere
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
}