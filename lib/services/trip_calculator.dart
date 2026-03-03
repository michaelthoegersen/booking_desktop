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

    /// Per-leg flag: if true, bridge cost is excluded for this leg
    List<bool>? noBridgePerLeg,

    /// Km subject to toll — Swedish km are excluded (toll-free in Sweden).
    /// Defaults to totalKm when not provided.
    double? tollableKm,

    /// Swedish km (toll-free) — stored in result for breakdown display
    double sweKm = 0,

    /// German km (toll-free) — stored in result for breakdown display
    double deKm = 0,
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

    final dd = calcDDriveDays(
      dates: dates,
      legKm: legKm,
      pickupEveningFirstDay: pickupEveningFirstDay,
      threshold: threshold,
      noDDrivePerLeg: noDDrivePerLeg,
    );

    final int totalDDriveDays = dd.dDriveDays;
    final int flightTickets   = dd.flightTickets;

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
    // ✅ FERRY + BRIDGE
    // ----------------------------------------

    final ferryAndBridge = FerryResolver.resolveFerriesAndBridges(
      ferries: ferries,
      trailer: trailer,
      ferryPerLeg: safeFerryPerLeg,
      noBridgePerLeg: noBridgePerLeg,
    );
    final double ferryCost = ferryAndBridge.ferryCost;
    final double bridgeCost = ferryAndBridge.bridgeCost;

    _log('FERRY COST: $ferryCost');
    _log('BRIDGE COST: $bridgeCost');

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
        bridgeCost +
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
      bridgeCost: bridgeCost,
      tollCost: tollCost,
      sweKm: sweKm,
      deKm: deKm,
      tollableKm: tollableKm ?? totalKm,
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
  // SHARED D.DRIVE DAY COUNT
  // ===================================================
  //
  // Used by both the Norwegian and Swedish pricing models so they
  // always produce the same D.Drive day count.
  //
  // Algorithm (calendar-date based):
  //   • Group km by calendar date; skip dates where ALL legs are noDDrive.
  //   • A date qualifies when km > threshold.
  //   • Cluster qualifying dates:
  //       diff ≤ 3 days → merge  (all span days count)
  //       diff ≥ 4 days → separate  (+1 after first cluster, +1 before next)
  //   • +1 travel day before the first cluster (if not at round start).
  //   • +1 travel day after  the last  cluster (if not at round end).
  static ({int dDriveDays, int flightTickets}) calcDDriveDays({
    required List<DateTime> dates,
    required List<double> legKm,
    required bool pickupEveningFirstDay,
    required double threshold,
    List<bool>? noDDrivePerLeg,
  }) {
    final int n = dates.length;
    if (n == 0) return (dDriveDays: 0, flightTickets: 0);

    final startIdx = pickupEveningFirstDay ? 1 : 0;
    if (startIdx >= n) return (dDriveDays: 0, flightTickets: 0);

    // Check each individual leg against the threshold.
    // A date qualifies for D.Drive if ANY single leg on that date
    // exceeds the threshold and is not marked noDDrive.
    final qualifyingDates = <DateTime>{};

    for (int i = startIdx; i < n; i++) {
      final d = DateTime(dates[i].year, dates[i].month, dates[i].day);
      final isExcluded = noDDrivePerLeg != null &&
          i < noDDrivePerLeg.length &&
          noDDrivePerLeg[i];
      if (!isExcluded && legKm[i] > threshold) {
        qualifyingDates.add(d);
      }
    }

    // Qualifying D.Drive dates
    final ddDates = qualifyingDates.toList()..sort();

    if (ddDates.isEmpty) return (dDriveDays: 0, flightTickets: 0);

    // Round boundaries for travel-day checks
    final effectiveStart = DateTime(
        dates[startIdx].year, dates[startIdx].month, dates[startIdx].day);
    final effectiveEnd =
        DateTime(dates.last.year, dates.last.month, dates.last.day);

    // Build clusters: merge dates that are ≤ 3 calendar days apart
    final clusters = <List<DateTime>>[];
    var current = [ddDates.first];
    for (int i = 1; i < ddDates.length; i++) {
      if (ddDates[i].difference(current.last).inDays <= 3) {
        current.add(ddDates[i]);
      } else {
        clusters.add(current);
        current = [ddDates[i]];
      }
    }
    clusters.add(current);

    int totalDD = 0;
    int tickets = 0;

    for (int ci = 0; ci < clusters.length; ci++) {
      final cFirst = clusters[ci].first;
      final cLast  = clusters[ci].last;

      // All calendar days from first to last D.Drive date in cluster
      totalDD += cLast.difference(cFirst).inDays + 1;

      // Travel day INTO the round (before first cluster)
      if (ci == 0 && cFirst != effectiveStart) {
        totalDD++;
        tickets++;
      }

      // Travel day OUT of the round (after last cluster)
      if (ci == clusters.length - 1 && cLast != effectiveEnd) {
        totalDD++;
        tickets++;
      }

      // Between separate clusters: +1 after this + +1 before next
      if (ci < clusters.length - 1) {
        final nextFirst = clusters[ci + 1].first;
        if (nextFirst.difference(cLast).inDays >= 4) {
          totalDD += 2;
          tickets += 2;
        }
      }
    }

    return (dDriveDays: totalDD, flightTickets: tickets);
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
      bridgeCost: 0,
      tollCost: 0,
      sweKm: 0,
      deKm: 0,
      tollableKm: 0,
      tollPerLeg: [],
      legKm: [],
      extraPerLeg: [],
      hasTravelBefore: [],
      totalCost: 0,
    );
  }
}