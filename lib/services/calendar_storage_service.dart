import '../supabase_clients.dart'; // der du definerer clients

class CalendarStorageService {

  static SupabaseClient get sb => Supabase.instance.client;

  static Future<void> insertToCalendar({
    required DateTime date,
    required String location,
    required String production,
    required String vehicle,
    required String bus,
    required String km,
    required String time,
    required String price,
    required String contact,
  }) async {

    await sb.from('samletdata').insert({
      'dato': date.toIso8601String().substring(0,10),
      'sted': location,
      'produksjon': production,
      'kjoretoy': vehicle,
      'km': km,
      'tid': time,
      'pris': price,
      'contact': contact,

      'status': 'Draft',
      'kilde': bus,
    });
  }
}