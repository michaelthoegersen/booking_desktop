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
  static Future<void> syncFromOffer(
  OfferDraft offer, {
  required String selectedBus,
  required String draftId,
}) async {
  try {
    print("📅 SYNC START: ${offer.production}");

    // --------------------------------------------------
    // 1️⃣ Hent eksisterende rader
    // --------------------------------------------------
    final existing = await sb
        .from('samletdata')
        .select('dato, kilde')
        .eq('draft_id', draftId);

    // Map: dato -> bus
    final Map<String, String> existingBusByDate = {};

    for (final r in existing) {
      final d = r['dato']?.toString();
      final b = r['kilde']?.toString();

      if (d != null && b != null && b.isNotEmpty) {
        existingBusByDate[d] = b;
      }
    }

    print("📦 Existing overrides: $existingBusByDate");

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
    // 3️⃣ Slett KUN rader som ikke finnes lenger
    // --------------------------------------------------
    // --------------------------------------------------
// 3️⃣ Slett KUN rader som ikke finnes lenger
// --------------------------------------------------
final dbDates = existingBusByDate.keys.toSet();

final toDelete = dbDates.difference(offerDates);

if (toDelete.isNotEmpty) {
  await sb
      .from('samletdata')
      .delete()
      .eq('draft_id', draftId)
      .inFilter('dato', toDelete.toList());

  print("🗑️ Deleted removed dates: $toDelete");
}

    // --------------------------------------------------
    // 4️⃣ Bygg nye rader
    // --------------------------------------------------
    final rows = <Map<String, dynamic>>[];

    for (int ri = 0; ri < offer.rounds.length; ri++) {
      final round = offer.rounds[ri];

      if (round.entries.isEmpty) continue;

      final entries = [...round.entries]
        ..sort((a, b) => a.date.compareTo(b.date));

      // Travel flags
      final List<bool> travelFlags = [];

      for (int i = 0; i < entries.length; i++) {
        travelFlags.add(_hasTravelBefore(entries, i));
      }

      // Calc
      final calc = TripCalculator.calculateRound(
        settings: SettingsStore.current,
        dates: entries.map((e) => e.date).toList(),
        pickupEveningFirstDay: round.pickupEveningFirstDay,
        trailer: round.trailer,
        totalKm: 0,
        legKm: const [],
        ferryCost: 0,
        tollCost: 0,
        hasTravelBefore: travelFlags,
      );

      final vehicle =
          "${offer.busType.label}${round.trailer ? ' + trailer' : ''}";

      // --------------------------------------------------
      // 5️⃣ Per dag
      // --------------------------------------------------
      for (final e in entries) {
        final dateStr =
            e.date.toIso8601String().substring(0, 10);

        // 👇 VELG BUS SMART
        final bus =
            existingBusByDate[dateStr] ?? selectedBus;

        rows.add({
          'draft_id': draftId,
          'dato': dateStr,

          'sted': e.location,
          'km': '',
          'tid': '',

          'produksjon': offer.production,
          'kjoretoy': vehicle,

          'pris': calc.totalCost.toString(),

          'contact': offer.contact,
          'status': 'Draft',

          // 🔥 BEHOLD OVERRIDE
          'kilde': bus,
        });
      }
    }

    print("📅 Rows to upsert: ${rows.length}");

    // --------------------------------------------------
    // 6️⃣ UPSERT (ikke insert)
    // --------------------------------------------------
    if (rows.isNotEmpty) {
      await sb
          .from('samletdata')
          .upsert(
            rows,
            onConflict: 'draft_id,dato',
          );

      print("✅ Upsert complete");
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

