import '../models/app_settings.dart';
import '../models/round_calc_result.dart';
import '../models/ferry_definition.dart';
import 'ferry_resolver.dart';

class TripCalculator {

  /// 🔧 Slå debug av/på her
  static const bool debug = true;

  static void _log(String msg) {
    if (debug) {
      // ignore: avoid_print
      print('[TRIP] $msg');
    }
  }

  static RoundCalcResult calculateRound({
    required AppSettings settings,
    required List<DateTime> dates,
    required bool pickupEveningFirstDay,
    required bool trailer,
    required double totalKm,
    required List<double> legKm,

    /// 🔥 Ferry-definisjoner fra DB / settings
    required List<FerryDefinition> ferries,

    /// 🆕 ferry_name per leg (fra routes_all)
    List<String?>? ferryPerLeg,

    /// 🟡 Legacy / UI (IKKE brukt til ferry-prising)
    required List<String> extraPerLeg,

    required List<double> tollPerLeg,
    required List<bool> hasTravelBefore,

    /// Per-leg flag: if true, this leg does NOT count as D.Drive
    List<bool>? noDDrivePerLeg,

    /// Km subject to toll — Swedish km are excluded (toll-free in Sweden).
    /// Defaults to totalKm when not provided.
    double? tollableKm,
  }) {
    // ✅ RIKTIG KILDE: dates er sannheten
    final int entryCount = dates.length;

    if (entryCount == 0 ||
        legKm.length != entryCount ||
        hasTravelBefore.length != entryCount ||
        tollPerLeg.length != entryCount ||
        extraPerLeg.length != entryCount ||
        (ferryPerLeg != null && ferryPerLeg.length != entryCount)) {
      _log('❌ Invalid input lengths → empty result');
      return _emptyResult();
    }

    // ===================================================
    // ✅ SAFE ferryPerLeg (aldri null-lister videre)
    // ===================================================
    final List<String?> safeFerryPerLeg =
        ferryPerLeg != null && ferryPerLeg.length == entryCount
            ? ferryPerLeg
            : List<String?>.filled(entryCount, null);

    _log('--- START ROUND CALC ---');
    _log('Trailer: $trailer');
    _log('Total km: $totalKm');
    _log('Ferry per leg: $safeFerryPerLeg');

    // ----------------------------------------
    // BILLABLE DAYS
    // ----------------------------------------

    final Set<String> uniqueDays = {};
    for (final d in dates) {
      uniqueDays.add('${d.year}-${d.month}-${d.day}');
    }

    int billableDays = uniqueDays.length;
    if (pickupEveningFirstDay && billableDays > 0) {
      billableDays -= 1;
    }

    _log('Billable days: $billableDays');

    // ----------------------------------------
    // KM
    // ----------------------------------------

    final double includedKm =
        billableDays * settings.includedKmPerDay;

    final double extraKm =
        (totalKm - includedKm).clamp(0.0, double.infinity);

    _log('Included km: $includedKm');
    _log('Extra km: $extraKm');

    // ----------------------------------------
    // BASE COSTS
    // ----------------------------------------

    final double dayCost =
        billableDays * settings.dayPrice;

    final double extraKmCost =
        extraKm * settings.extraKmPrice;

    _log('Day cost: $dayCost');
    _log('Extra km cost: $extraKmCost');

    // ----------------------------------------
    // D.DRIVE LOGIC
    // ----------------------------------------

    final double threshold = settings.dDriveKmThreshold;
    final double hardLimit = threshold * 2;

    // --------------------------------------------------
// D.DRIVE START INDEX (IGNORE PICKUP EVENING)
// --------------------------------------------------

final int startIndex =
    pickupEveningFirstDay ? 1 : 0;

final Map<String, List<int>> dayToIndexes = {};

for (int i = startIndex; i < entryCount; i++) {
  final d = dates[i];
  final key = '${d.year}-${d.month}-${d.day}';

  dayToIndexes.putIfAbsent(key, () => []);
  dayToIndexes[key]!.add(i);
}

    final Map<String, double> dayKm = {};
    dayToIndexes.forEach((day, idx) {
      dayKm[day] = idx.fold(0.0, (s, i) => s + legKm[i]);
    });

    final List<int> dDriveIndexes = [];

    for (final e in dayToIndexes.entries) {
      // Skip if ALL legs on this day are marked no-D.Drive
      if (noDDrivePerLeg != null &&
          e.value.every((i) => i < noDDrivePerLeg.length && noDDrivePerLeg[i])) {
        continue;
      }

      final km = dayKm[e.key] ?? 0;
      if (km < threshold) continue;

      final bool hadTravel =
          e.value.any((i) => hasTravelBefore[i]);

      if (hadTravel && km < hardLimit) continue;

      dDriveIndexes.addAll(e.value);
    }

    dDriveIndexes.sort();

    final List<List<int>> clusters = [];
    List<int> current = [];

    for (final idx in dDriveIndexes) {
      if (current.isEmpty || idx - current.last <= 2) {
        current.add(idx);
      } else {
        clusters.add(List.from(current));
        current = [idx];
      }
    }

    if (current.isNotEmpty) clusters.add(current);

    final int baseDDriveDays = dayToIndexes.entries.where((e) {
      if (noDDrivePerLeg != null &&
          e.value.every((i) => i < noDDrivePerLeg.length && noDDrivePerLeg[i])) {
        return false;
      }
      return (dayKm[e.key] ?? 0) >= threshold;
    }).length;

    int extraDays = 0;
    int flightTickets = 0;

    // --------------------------------------------------
// RESPECT PICKUP EVENING FOR D.DRIVE EDGES
// --------------------------------------------------

final int endIndex = entryCount - 1;

for (final c in clusters) {
  if (c.first != startIndex) {
    extraDays++;
    flightTickets++;
  }

  if (c.last != endIndex) {
    extraDays++;
    flightTickets++;
  }
}

    final int totalDDriveDays =
        baseDDriveDays + extraDays;

    final double dDriveCost =
        totalDDriveDays * settings.dDriveDayPrice;

    final double flightCost =
        flightTickets * settings.flightTicketPrice;

    _log('DDrive days: $totalDDriveDays');
    _log('DDrive cost: $dDriveCost');
    _log('Flight tickets: $flightTickets');
    _log('Flight cost: $flightCost');

    // ----------------------------------------
    // TRAILER
    // ----------------------------------------

    double trailerDayCost = 0;
    double trailerKmCost = 0;

    if (trailer) {
      trailerDayCost =
          billableDays * settings.trailerDayPrice;
      trailerKmCost =
          totalKm * settings.trailerKmPrice;
    }

    _log('Trailer day cost: $trailerDayCost');
    _log('Trailer km cost: $trailerKmCost');

    // ----------------------------------------
    // ✅ FERRY – KUN ferry_name
    // ----------------------------------------

    final double ferryCost =
        FerryResolver.resolveTotalFerryCost(
          ferries: ferries,
          trailer: trailer,
          ferryPerLeg: safeFerryPerLeg,
        );

    _log('FERRY COST: $ferryCost');

    // ----------------------------------------
    // TOLL (midlertidig fast modell)
    // ----------------------------------------

    final double tollCost = (tollableKm ?? totalKm) * settings.tollKmRate;
    _log('Toll cost: $tollCost');

    // ----------------------------------------
    // TOTAL
    // ----------------------------------------

    final double totalCost =
        dayCost +
        extraKmCost +
        dDriveCost +
        trailerDayCost +
        trailerKmCost +
        ferryCost +
        flightCost +
        tollCost;

    _log('TOTAL COST: $totalCost');
    _log('--- END ROUND CALC ---');

    return RoundCalcResult(
      billableDays: billableDays,
      includedKm: includedKm,
      extraKm: extraKm,
      dayCost: dayCost,
      extraKmCost: extraKmCost,
      dDriveDays: totalDDriveDays,
      dDriveCost: dDriveCost,
      flightTickets: flightTickets,
      flightCost: flightCost,
      trailerDayCost: trailerDayCost,
      trailerKmCost: trailerKmCost,
      ferryCost: ferryCost,
      tollCost: tollCost,
      tollPerLeg: List<double>.from(tollPerLeg),
      legKm: List<double>.from(legKm),
      extraPerLeg: List<String>.from(extraPerLeg),
      hasTravelBefore: List<bool>.from(hasTravelBefore),
      noDDrivePerLeg: noDDrivePerLeg != null
          ? List<bool>.from(noDDrivePerLeg)
          : List<bool>.filled(legKm.length, false),
      totalCost: totalCost,
    );
  }

  // ===================================================
  // EMPTY RESULT
  // ===================================================

  static RoundCalcResult _emptyResult() {
    return const RoundCalcResult(
      billableDays: 0,
      includedKm: 0,
      extraKm: 0,
      dayCost: 0,
      extraKmCost: 0,
      dDriveDays: 0,
      dDriveCost: 0,
      flightTickets: 0,
      flightCost: 0,
      trailerDayCost: 0,
      trailerKmCost: 0,
      ferryCost: 0,
      tollCost: 0,
      tollPerLeg: [],
      legKm: [],
      extraPerLeg: [],
      hasTravelBefore: [],
      totalCost: 0,
    );
  }
}