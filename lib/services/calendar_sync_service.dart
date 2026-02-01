import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';
import '../services/trip_calculator.dart';
import '../state/settings_store.dart';
import '../supabase_clients.dart';

class CalendarSyncService {
  static SupabaseClient get sb => Supabase.instance.client;

  // --------------------------------------------------
  // Helper: Sjekk om det finnes Travel/Off før index
  // --------------------------------------------------
  static bool _hasTravelBefore(
    List<RoundEntry> entries,
    int index,
  ) {
    if (index <= 0) return false;

    int i = index - 1;

    while (i >= 0) {
      final loc = entries[i].location.trim().toLowerCase();

      if (loc == 'travel' || loc == 'off') {
        return true;
      }

      if (loc.isNotEmpty) {
        return false;
      }

      i--;
    }

    return false;
  }

  /// Sync offer → samletdata (kalender)
  /// Sync offer → samletdata (kalender)
static Future<void> syncFromOffer(
  OfferDraft offer, {
  required String selectedBus,
  required String draftId,
}) async {
  try {
    print("📅 SYNC START: ${offer.production}");
    print("📌 STATUS: ${offer.status}");

    // --------------------------------------------------
    // 1️⃣ Hent eksisterende rader
    // --------------------------------------------------
    final existing = await sb
        .from('samletdata')
        .select('dato, kilde')
        .eq('draft_id', draftId);

    final Map<String, String> existingBusByDate = {};

    for (final r in existing) {
      final d = r['dato']?.toString();
      final b = r['kilde']?.toString();

      if (d != null && b != null && b.isNotEmpty) {
        existingBusByDate[d] = b;
      }
    }

    // --------------------------------------------------
    // 2️⃣ Finn alle datoer i offer
    // --------------------------------------------------
    final Set<String> offerDates = {};

    for (final r in offer.rounds) {
      for (final e in r.entries) {
        final d =
            e.date.toIso8601String().substring(0, 10);

        offerDates.add(d);
      }
    }

    if (offerDates.isEmpty) {
      print("⚠️ Ingen datoer → avbryter sync");
      return;
    }

    // --------------------------------------------------
    // 3️⃣ Slett gamle rader
    // --------------------------------------------------
    final dbDates = existingBusByDate.keys.toSet();

    final toDelete = dbDates.difference(offerDates);

    if (toDelete.isNotEmpty) {
      await sb
          .from('samletdata')
          .delete()
          .eq('draft_id', draftId)
          .inFilter('dato', toDelete.toList());

      print("🗑️ Deleted: $toDelete");
    }

    // --------------------------------------------------
// 4️⃣ Bygg nye rader (AGGREGER PER DATO)
// --------------------------------------------------

final Map<String, Map<String, dynamic>> rowByDate = {};

for (final round in offer.rounds) {
  if (round.entries.isEmpty) continue;

  final entries = [...round.entries]
    ..sort((a, b) => a.date.compareTo(b.date));

  final calc = TripCalculator.calculateRound(
    settings: SettingsStore.current,
    dates: entries.map((e) => e.date).toList(),
    pickupEveningFirstDay: round.pickupEveningFirstDay,
    trailer: round.trailer,
    totalKm: 0,
    legKm: const [],
    ferryCost: 0,
    tollCost: 0,
    hasTravelBefore:
        List.generate(entries.length, (i) => _hasTravelBefore(entries, i)),
  );

  final vehicle =
      "${offer.busType.label}${round.trailer ? ' + trailer' : ''}";

  for (final e in entries) {
    final dateStr =
        e.date.toIso8601String().substring(0, 10);

    final bus =
        existingBusByDate[dateStr] ?? selectedBus;

    // Finn / opprett rad
    final row = rowByDate.putIfAbsent(dateStr, () {
      return {
        'draft_id': draftId,
        'dato': dateStr,

        'sted': '',
        'km': '',
        'tid': '',

        'produksjon': offer.production,
        'kjoretoy': vehicle,

        'pris': calc.totalCost.toString(),

        'contact': offer.contact,

        'status': offer.status,

        'kilde': bus,
      };
    });

    // Append steder
    final loc = e.location.trim();

    if (loc.isNotEmpty) {
      if ((row['sted'] as String).isEmpty) {
        row['sted'] = loc;
      } else {
        row['sted'] = '${row['sted']}, $loc';
      }
    }
  }
}

final rows = rowByDate.values.toList();

    // --------------------------------------------------
    // 5️⃣ UPSERT
    // --------------------------------------------------
    if (rows.isNotEmpty) {
      await sb
          .from('samletdata')
          .upsert(
            rows,
            onConflict: 'draft_id,dato',
          );

      print("✅ Upsert: ${rows.length}");
    }

    print("📅 SYNC DONE");

  } catch (e, st) {
    print("❌ CALENDAR SYNC ERROR");
    print(e);
    print(st);
    rethrow;
  }
}
}
