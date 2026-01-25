import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route_result.dart';

class DistanceService {
  final SupabaseClient _client = Supabase.instance.client;

  // ------------------------------------------------------------
  // Utils
  // ------------------------------------------------------------
  String _norm(String s) => s.trim();

  // ------------------------------------------------------------
  // Find single route (for calculator / planner)
  // ------------------------------------------------------------
  Future<RouteResult?> findRoute({
    required String from,
    required String to,
  }) async {
    final a = _norm(from);
    final b = _norm(to);

    if (a.isEmpty || b.isEmpty) return null;

    try {
      // 1️⃣ Exact match
      final exact = await _client
          .from('routes_all')
          .select()
          .eq('from_place', a)
          .eq('to_place', b)
          .limit(1);

      if (exact is List && exact.isNotEmpty) {
        return _fromRow(exact.first);
      }

      // 2️⃣ Reverse match
      final reverse = await _client
          .from('routes_all')
          .select()
          .eq('from_place', b)
          .eq('to_place', a)
          .limit(1);

      if (reverse is List && reverse.isNotEmpty) {
        return _fromRow(reverse.first);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // Autocomplete places
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
  // Load all routes (planner list)
  // ------------------------------------------------------------
  Future<List<RouteResult>> getAllRoutes() async {
    try {
      final res = await _client
          .from('routes_all')
          .select()
          .order('from_place');

      if (res is! List) return [];

      return res
          .map<RouteResult>((r) => _fromRow(r))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------------
  // Convert DB row → RouteResult
  // ------------------------------------------------------------
  RouteResult _fromRow(Map<String, dynamic> r) {
    return RouteResult(
      id: r['id'].toString(),
      from: r['from_place'] ?? '',
      to: r['to_place'] ?? '',
      km: (r['distance_total_km'] as num).toDouble(),
      durationMin: r['duration_min'] ?? 0,
      summary: r['extra'] ?? '',
    );
  }
}