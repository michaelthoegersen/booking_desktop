import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';
import '../services/trip_calculator.dart';
import '../state/settings_store.dart';
import '../supabase_clients.dart';
import '../models/round_calc_result.dart';
import '../state/active_company.dart';

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

      if (loc == 'travel') {
        return true;   // only Travel triggers the 1200km threshold
      }

      if (loc.isNotEmpty) {
        return false;  // Off or any real city stops the search → normal 600km threshold
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
      // 3️⃣b  Slett foreldreløse rader (draft_id = NULL)
      // Disse ble opprettet av _assign() før draft_id-fiksing.
      // De matcher ikke .eq('draft_id', draftId) over.
      // --------------------------------------------------
      if (offer.production.isNotEmpty && offer.contact.isNotEmpty) {
        await sb
            .from('samletdata')
            .delete()
            .eq('produksjon', offer.production)
            .eq('contact', offer.contact)
            .inFilter('dato', offerDates.toList())
            .or('draft_id.is.null')
            .or('manual_block.is.null,manual_block.eq.false');

        print("♻️ Cleared orphaned rows (no draft_id) for ${offer.production}");
      }

      // --------------------------------------------------
      // 4️⃣ Bygg nye rader (ENTERPRISE)
      // --------------------------------------------------

      // If there's a totalOverride on the offer, distribute it
      // proportionally across rounds (based on calculated share).
      final totalOverride = offer.totalOverride;
      double? _calcTotalSum;
      if (totalOverride != null) {
        _calcTotalSum = 0;
        for (final calc in calcCache.values) {
          _calcTotalSum = _calcTotalSum! + calc.totalCost;
        }
      }

      final Map<String, Map<String, dynamic>> rowByDate = {};

      for (int ri = 0; ri < offer.rounds.length; ri++) {
        final round = offer.rounds[ri];

        if (round.entries.isEmpty) continue;

        final calc = calcCache[ri];
        if (calc == null) continue;

        // Use override price if set, distributed proportionally
        final double roundPris;
        if (totalOverride != null) {
          final sum = _calcTotalSum!;
          if (sum > 0) {
            roundPris = totalOverride * (calc.totalCost / sum);
          } else {
            // All rounds have 0 cost — put entire override on first active round
            roundPris = (ri == calcCache.keys.first) ? totalOverride : 0;
          }
        } else {
          roundPris = calc.totalCost;
        }

        final vehicle =
            "${offer.busType.label}${round.trailer ? ' + trailer' : ''}";

        // ENTERPRISE MULTI BUS SUPPORT — include WAITING_LIST as a valid kilde
        final buses = round.busSlots
            .whereType<String>()
            .where((b) => b.isNotEmpty)
            .toList();

        if (buses.isEmpty) {
          print("⛔ Skip round $ri — no bus selected");
          continue;
        }

        for (int i = 0; i < round.entries.length; i++) {
          final e = round.entries[i];

          final dateStr =
              e.date.toIso8601String().substring(0, 10);

          // ⭐⭐⭐ EN RAD PER BUSS ⭐⭐⭐
          for (final bus in buses) {
            final key = "$dateStr-$bus";

            final row = rowByDate.putIfAbsent(key, () {
              final legNoDDrive = (calc.noDDrivePerLeg != null &&
                      i < calc.noDDrivePerLeg!.length)
                  ? calc.noDDrivePerLeg![i]
                  : false;
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
                'pris': roundPris.toString(),
                'contact': offer.contact,
                'status': offer.status,
                'kilde': bus,
                'no_ddrive': legNoDDrive,
                if (activeCompanyNotifier.value != null)
                  'owner_company_id': activeCompanyNotifier.value!.id,
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