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

  final int flightTickets;
  final double flightCost;

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

    required this.flightTickets,
    required this.flightCost,

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
    // SAFETY
    // ----------------------------------------

    if (entryCount == 0) {
      return _emptyResult();
    }

    if (hasTravelBefore.length != entryCount) {
      return _emptyResult();
    }

    if (tollPerLeg.length != entryCount) {
      return _emptyResult();
    }

    if (extraPerLeg.length != entryCount) {
      return _emptyResult();
    }

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
// D.DRIVE + TRAVEL
// ----------------------------------------

final List<int> dDriveIndexes = [];

final double threshold = settings.dDriveKmThreshold;
final double hardLimit = threshold * 2;

// Finn alle DDrive-dager
for (int i = 0; i < entryCount; i++) {
  final km = legKm[i];
  final hadTravel = hasTravelBefore[i];

  if (km <= 0) continue;
  if (km < threshold) continue;

  if (hadTravel && km < hardLimit) continue;

  dDriveIndexes.add(i);
}

// Gruppér sammenhengende
final List<List<int>> groups = [];

for (final idx in dDriveIndexes) {
  if (groups.isEmpty) {
    groups.add([idx]);
    continue;
  }

  final last = groups.last.last;

  if (idx == last + 1) {
    groups.last.add(idx);
  } else {
    groups.add([idx]);
  }
}

// Tell dager + reise
int dDriveDays = 0;
int travelDays = 0;
int flightTickets = 0;

for (final g in groups) {
  dDriveDays += g.length;

  // Før/etter hvis alene eller langt fra andre
  travelDays += 2;
  flightTickets += 2;
}

// Kostnader
final double dDriveCost =
    dDriveDays * settings.dDriveDayPrice;

final double flightCost =
    flightTickets * settings.flightTicketPrice;

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
        flightCost +
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

      flightTickets: flightTickets,
      flightCost: flightCost,

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