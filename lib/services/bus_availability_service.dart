import 'package:supabase_flutter/supabase_flutter.dart';

class BusAvailabilityService {
  static final _supabase = Supabase.instance.client;

  /// Result model
  static Future<Map<String, bool>> fetchAvailability({
    required DateTime start,
    required DateTime end,
  }) async {
    // --------------------------------------------------
    // 1️⃣ Hent alle busser
    // --------------------------------------------------

    final busesRes = await _supabase
        .from('buses')
        .select('name');

    final allBuses =
        (busesRes as List).map((e) => e['name'] as String).toList();

    // --------------------------------------------------
    // 2️⃣ Hent BUSSER SOM ER OPPTATT I PERIODEN
    // --------------------------------------------------

    final busyRes = await _supabase
        .from('calendar')
        .select('bus,start_date,end_date,status')
        .lte('start_date', end.toIso8601String())
        .gte('end_date', start.toIso8601String());

    final busy = (busyRes as List)
        .where((e) => e['status'] != 'Cancelled')
        .map((e) => e['bus'] as String)
        .toSet();

    // --------------------------------------------------
    // 3️⃣ Lag availability map
    // --------------------------------------------------

    final Map<String, bool> result = {};

    for (final bus in allBuses) {
      result[bus] = !busy.contains(bus);
    }

    return result;
  }
}