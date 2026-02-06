import '../supabase_clients.dart';

class CalendarManualService {
  static SupabaseClient get sb => Supabase.instance.client;

  static Future<void> createBlock({
    required DateTime from,
    required DateTime to,
    required String bus,
    String? note,
  }) async {

    final days = to.difference(from).inDays;

    final rows = <Map<String, dynamic>>[];

    for (int i = 0; i <= days; i++) {
      final d = from.add(Duration(days: i));

      rows.add({
        'dato': d.toIso8601String().substring(0,10),
        'kilde': bus,

        'status': 'Blocked',
        'manual_block': true,
        'note': note ?? '',

        'produksjon': 'RESERVED',
        'kjoretoy': '',
        'sted': '',
        'km': '',
        'tid': '',
        'pris': '',
        'contact': '',
      });
    }

    await sb.from('samletdata').insert(rows);
  }
}