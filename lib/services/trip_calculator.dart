// lib/services/trip_calculator.dart

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

  final double totalCost;

  // 👇 BRUKES I PDF
  final List<double> legKm;

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
    required this.totalCost,
    required this.legKm,
  });
}


// =======================================================
// MAIN CALCULATOR
// =======================================================

class TripCalculator {

  static RoundCalcResult calculateRound({
    required AppSettings settings,
    required int entryCount,
    required bool pickupEveningFirstDay,
    required bool trailer,
    required double totalKm,
    required List<double> legKm,
    required double ferryCost,
    required double tollCost,
    required List<bool> hasTravelBefore,
  }) {

    // ----------------------------------------
    // SAFETY (NO CRASH)
    // ----------------------------------------

    if (entryCount == 0) {
      return _emptyResult();
    }

    if (legKm.length != entryCount ||
        hasTravelBefore.length != entryCount) {
      return _emptyResult();
    }


    // ----------------------------------------
    // BILLABLE DAYS
    // ----------------------------------------

    int billableDays = entryCount;

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
// D.DRIVE (FINAL LOGIC)
// ----------------------------------------

int dDriveDays = 0;

final double threshold = settings.dDriveKmThreshold;
final double hardLimit = threshold * 2;

for (int i = 0; i < entryCount; i++) {

  final double km = legKm[i];
  final bool hadTravel = hasTravelBefore[i];

  // ---------- NO DRIVE ----------
  if (km <= 0) continue;

  // ---------- UNDER 600 ----------
  if (km < threshold) continue;

  // ---------- TRAVEL BEFORE ----------
  if (hadTravel) {

    // Under 1200 → ignore
    if (km < hardLimit) continue;

    // Over 1200 → allow
    dDriveDays++;
    continue;
  }

  // ---------- NORMAL ----------
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

      totalCost: totalCost,

      legKm: List<double>.from(legKm),
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

      totalCost: 0,

      legKm: [],
    );
  }
}