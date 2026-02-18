import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';
import '../services/trip_calculator.dart';
import '../state/settings_store.dart';
import '../supabase_clients.dart';
import '../models/round_calc_result.dart';

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
    required String draftId,
    required Map<int, RoundCalcResult> calcCache,
  }) async {
    try {
      print("📅 SYNC START: ${offer.production}");
      print("📌 STATUS: ${offer.status}");

      for (int i = 0; i < offer.rounds.length; i++) {
        print("ROUND $i BUSSLOTS = ${offer.rounds[i].busSlots}");
      }

      // --------------------------------------------------
      // 1️⃣ Hent eksisterende rader
      // --------------------------------------------------
      final existing = await sb
          .from('samletdata')
          .select('dato, kilde')
          .eq('draft_id', draftId)
          .eq('manual_block', false);

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
          final d = e.date.toIso8601String().substring(0, 10);
          offerDates.add(d);
        }
      }

      if (offerDates.isEmpty) {
        print("⚠️ Ingen datoer → avbryter sync");
        return;
      }

      // --------------------------------------------------
      // 3️⃣ ENTERPRISE RESET FOR THIS DRAFT
      // 🔥 FIX: slett også manual_block IS NULL
      // --------------------------------------------------
      await sb
          .from('samletdata')
          .delete()
          .eq('draft_id', draftId)
          .or('manual_block.is.null,manual_block.eq.false');

      print("♻️ Cleared previous auto rows for draft");

      // --------------------------------------------------
      // 4️⃣ Bygg nye rader (ENTERPRISE)
      // --------------------------------------------------
      final Map<String, Map<String, dynamic>> rowByDate = {};

      for (int ri = 0; ri < offer.rounds.length; ri++) {
        final round = offer.rounds[ri];

        if (round.entries.isEmpty) continue;

        final calc = calcCache[ri];
        if (calc == null) continue;

        final vehicle =
            "${offer.busType.label}${round.trailer ? ' + trailer' : ''}";

        for (int i = 0; i < round.entries.length; i++) {
          final e = round.entries[i];

          final dateStr =
              e.date.toIso8601String().substring(0, 10);

          // ENTERPRISE MULTI BUS SUPPORT
          final buses = round.busSlots
              .whereType<String>()
              .where((b) => b.isNotEmpty)
              .toList();

          if (buses.isEmpty) {
            print("⛔ Skip round $ri — no bus selected");
            continue;
          }

          // ⭐⭐⭐ EN RAD PER BUSS ⭐⭐⭐
          for (final bus in buses) {
            final key = "$dateStr-$bus";

            final row = rowByDate.putIfAbsent(key, () {
              return {
                'draft_id': draftId,
                'round_index': ri,
                'round_id': '$draftId-$ri',
                'dato': dateStr,
                'sted': '',
                'km': calc.legKm.length > i
                    ? calc.legKm[i].toString()
                    : '',
                'tid': '',
                'produksjon': offer.production,
                'kjoretoy': vehicle,
                'pris': calc.totalCost.toString(),
                'contact': offer.contact,
                'status': offer.status,
                'kilde': bus,
              };
            });

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
      }

      final rows = rowByDate.values.toList();

      // --------------------------------------------------
      // 5️⃣ UPSERT (BEHOLDT)
      // --------------------------------------------------
      if (rows.isNotEmpty) {
        await sb.from('samletdata').upsert(
          rows,
          onConflict: 'draft_id,dato,kilde',
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