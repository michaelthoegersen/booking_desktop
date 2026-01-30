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
      print("🚌 BUS: $selectedBus");

      // --------------------------------------------------
      // 1️⃣ Finn alle datoer
      // --------------------------------------------------
      final dates = <DateTime>[];

      for (final r in offer.rounds) {
        for (final e in r.entries) {
          dates.add(
            DateTime(
              e.date.year,
              e.date.month,
              e.date.day,
            ),
          );
        }
      }

      if (dates.isEmpty) {
        print("⚠️ Ingen datoer → avbryter sync");
        return;
      }

      final uniqueDates = dates.toSet().toList();

      final dateStrings = uniqueDates
          .map((d) => d.toIso8601String().substring(0, 10))
          .toList();

      print("📅 Dates: $dateStrings");

      // --------------------------------------------------
      // 2️⃣ Slett gamle rader
      // --------------------------------------------------
      final del = await sb
          .from('samletdata')
          .delete()
          .eq('draft_id', draftId)
          .select();

      print("🗑️ Deleted: ${del.length} rows");

      // --------------------------------------------------
      // 3️⃣ Bygg nye rader
      // --------------------------------------------------
      final rows = <Map<String, dynamic>>[];

      for (int ri = 0; ri < offer.rounds.length; ri++) {
        final round = offer.rounds[ri];

        if (round.entries.isEmpty) continue;

        final entries = [...round.entries]
          ..sort((a, b) => a.date.compareTo(b.date));

        // --------------------------------------------------
        // BUILD TRAVEL FLAGS (ekte)
        // --------------------------------------------------
        final List<bool> travelFlags = [];

        for (int i = 0; i < entries.length; i++) {
          final hasTravel = _hasTravelBefore(entries, i);
          travelFlags.add(hasTravel);
        }

        // --------------------------------------------------
        // Kalkuler pris per runde
        // --------------------------------------------------
        final calc = TripCalculator.calculateRound(
          settings: SettingsStore.current,
          entryCount: entries.length,
          pickupEveningFirstDay: round.pickupEveningFirstDay,
          trailer: round.trailer,
          totalKm: 0,
          legKm: const [],
          ferryCost: 0,
          tollCost: 0,

          // 👇 RIKTIG travel info
          hasTravelBefore: travelFlags,
        );

        // --------------------------------------------------
        // Kjøretøytekst
        // --------------------------------------------------
        final vehicle =
            "${offer.busType.label}${round.trailer ? ' + trailer' : ''}";

        // --------------------------------------------------
        // Bygg rader
        // --------------------------------------------------
        for (final e in entries) {
          final dateStr =
              e.date.toIso8601String().substring(0, 10);

          rows.add({
            'draft_id': draftId,

            // ---------------- DATO ----------------
            'dato': dateStr,

            // ---------------- RUTE ----------------
            'sted': e.location,
            'km': '',
            'tid': '',

            // ---------------- PRODUKSJON ----------------
            'produksjon': offer.production,
            'kjoretoy': vehicle,

            // ---------------- PRIS ----------------
            'pris': calc.totalCost.toString(),

            // ---------------- META ----------------
            'contact': offer.contact,
            'status': 'Draft',

            // ---------------- BUS ----------------
            'kilde': selectedBus,
          });
        }
      }

      print("📅 Rows to insert: ${rows.length}");

      // --------------------------------------------------
      // 4️⃣ Insert
      // --------------------------------------------------
      if (rows.isNotEmpty) {
        final ins = await sb
            .from('samletdata')
            .insert(rows)
            .select();

        print("✅ Inserted: ${ins.length} rows");
      } else {
        print("⚠️ Ingen rader å sette inn");
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