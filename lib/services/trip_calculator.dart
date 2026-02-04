import '../models/app_settings.dart';

// =======================================================
// RESULT MODEL
// =======================================================

class RoundCalcResult {
  final int billableDays;

  final double includedKm;
  final double extraKm;

  final double dayCost;
  final double extraKmCost;

  final int dDriveDays;
  final double dDriveCost;

  final double trailerDayCost;
  final double trailerKmCost;

  final double ferryCost;
  final double tollCost;

  // ✅ Toll per leg
  final List<double> tollPerLeg;

  // ✅ Km per leg
  final List<double> legKm;

  // ✅ Ferry / Bridge per leg
  final List<String> extraPerLeg;

  // ✅ Travel-flag per leg
  final List<bool> hasTravelBefore;

  final double totalCost;

  const RoundCalcResult({
    required this.billableDays,

    required this.includedKm,
    required this.extraKm,

    required this.dayCost,
    required this.extraKmCost,

    required this.dDriveDays,
    required this.dDriveCost,

    required this.trailerDayCost,
    required this.trailerKmCost,

    required this.ferryCost,
    required this.tollCost,

    required this.tollPerLeg,

    required this.legKm,

    required this.extraPerLeg,

    // ✅ NY
    required this.hasTravelBefore,

    required this.totalCost,
  });
}

// =======================================================
// MAIN CALCULATOR
// =======================================================

class TripCalculator {

  static RoundCalcResult calculateRound({
    required AppSettings settings,
    required List<DateTime> dates,
    required bool pickupEveningFirstDay,
    required bool trailer,
    required double totalKm,
    required List<double> legKm,
    required double ferryCost,
    required double tollCost,

    // ✅
    required List<double> tollPerLeg,

    // ✅
    required List<String> extraPerLeg,

    // ✅
    required List<bool> hasTravelBefore,
  }) {

    // ----------------------------------------
    // ENTRY COUNT
    // ----------------------------------------

    final int entryCount = legKm.length;

    // ----------------------------------------
// SAFETY (FIX FOR TRAVEL / OFF)
// ----------------------------------------

if (entryCount == 0) {
  return _emptyResult();
}

// Klipp alle lister til samme lengde
final safeLen = [
  legKm.length,
  hasTravelBefore.length,
  tollPerLeg.length,
  extraPerLeg.length,
].reduce((a, b) => a < b ? a : b);

final safeLegKm = legKm.take(safeLen).toList();
final safeTravel = hasTravelBefore.take(safeLen).toList();
final safeToll = tollPerLeg.take(safeLen).toList();
final safeExtra = extraPerLeg.take(safeLen).toList();

    // ----------------------------------------
    // BILLABLE DAYS
    // ----------------------------------------

    final Set<String> uniqueDays = {};

    for (final d in dates) {
      final key = '${d.year}-${d.month}-${d.day}';
      uniqueDays.add(key);
    }

    int billableDays = uniqueDays.length;

    if (pickupEveningFirstDay && billableDays > 0) {
      billableDays -= 1;
    }

    // ----------------------------------------
    // INCLUDED KM
    // ----------------------------------------

    final double includedKm =
        billableDays * settings.includedKmPerDay;

    // ----------------------------------------
    // EXTRA KM
    // ----------------------------------------

    final double extraKm =
        (totalKm - includedKm).clamp(0.0, double.infinity);

    // ----------------------------------------
    // DAY COST
    // ----------------------------------------

    final double dayCost =
        billableDays * settings.dayPrice;

    // ----------------------------------------
    // EXTRA KM COST
    // ----------------------------------------

    final double extraKmCost =
        extraKm * settings.extraKmPrice;

    // ----------------------------------------
    // D.DRIVE
    // ----------------------------------------

    int dDriveDays = 0;

    final double threshold = settings.dDriveKmThreshold;
    final double hardLimit = threshold * 2;

    for (int i = 0; i < entryCount; i++) {

      final double km = legKm[i];
      final bool hadTravel = hasTravelBefore[i];

      if (km <= 0) continue;
      if (km < threshold) continue;

      // Travel-regel
      if (hadTravel) {

        if (km < hardLimit) continue;

        dDriveDays++;
        continue;
      }

      // Normal dag
      dDriveDays++;
    }

    final double dDriveCost =
        dDriveDays * settings.dDriveDayPrice;

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
        tollCost;

    // ----------------------------------------
    // RESULT
    // ----------------------------------------

    return RoundCalcResult(
      billableDays: billableDays,

      includedKm: includedKm,
      extraKm: extraKm,

      dayCost: dayCost,
      extraKmCost: extraKmCost,

      dDriveDays: dDriveDays,
      dDriveCost: dDriveCost,

      trailerDayCost: trailerDayCost,
      trailerKmCost: trailerKmCost,

      ferryCost: ferryCost,
      tollCost: tollCost,

      tollPerLeg: List<double>.from(tollPerLeg),

      legKm: List<double>.from(legKm),

      extraPerLeg: List<String>.from(extraPerLeg),

      // ✅ VIKTIG
      hasTravelBefore: List<bool>.from(hasTravelBefore),

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