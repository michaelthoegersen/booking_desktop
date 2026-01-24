import '../models/app_settings.dart';

class RoundCalcResult {
  final int billableDays;

  final double totalKm;
  final double includedKm;
  final double extraKm;

  final int dDriveDays;
  final int flightTickets;

  final double dayCost;
  final double extraKmCost;

  final double trailerDayCost;
  final double trailerKmCost;

  final double dDriveCost;
  final double flightCost;

  final double ferryCost;
  final double tollCost;

  final double totalCost;

  // ✅ Stored per-leg km for PDF rows
  final List<double> legKm;

  const RoundCalcResult({
    required this.billableDays,
    required this.totalKm,
    required this.includedKm,
    required this.extraKm,
    required this.dDriveDays,
    required this.flightTickets,
    required this.dayCost,
    required this.extraKmCost,
    required this.trailerDayCost,
    required this.trailerKmCost,
    required this.dDriveCost,
    required this.flightCost,
    required this.ferryCost,
    required this.tollCost,
    required this.totalCost,
    required this.legKm,
  });
}

class TripCalculator {
  static RoundCalcResult calculateRound({
    required AppSettings settings,
    required int entryCount, // ⚠️ entryCount = ANTALL UNIKE DATOER
    required bool pickupEveningFirstDay,
    required bool trailer,
    required double totalKm,
    required List<double> legKm,
    required double ferryCost,
    required double tollCost,
  }) {
    // ------------------------------------------------------------
    // Billable days
    // ------------------------------------------------------------
    int billableDays = entryCount;

    if (pickupEveningFirstDay && billableDays > 0) {
      billableDays -= 1;
    }

    if (billableDays < 0) {
      billableDays = 0;
    }

    // ------------------------------------------------------------
    // Included / extra km
    // ------------------------------------------------------------
    final includedKm = billableDays * settings.includedKmPerDay;
    final extraKm =
        (totalKm - includedKm).clamp(0, double.infinity).toDouble();

    // ------------------------------------------------------------
    // D.Drive days (per leg)
    // ------------------------------------------------------------
    int dDriveDays = 0;
    for (final km in legKm) {
      if (km >= settings.dDriveKmThreshold) {
        dDriveDays++;
      }
    }

    // ------------------------------------------------------------
    // Flights (placeholder – ready for future logic)
    // ------------------------------------------------------------
    const int flightTickets = 0;

    // ------------------------------------------------------------
    // Costs
    // ------------------------------------------------------------
    final dayCost = billableDays * settings.dayPrice;
    final extraKmCost = extraKm * settings.extraKmPrice;

    final trailerDayCost =
        trailer ? billableDays * settings.trailerDayPrice : 0.0;
    final trailerKmCost =
        trailer ? totalKm * settings.trailerKmPrice : 0.0;

    final dDriveCost = dDriveDays * settings.dDriveDayPrice;
    final flightCost = flightTickets * settings.flightTicketPrice;

    final totalCost = dayCost +
        extraKmCost +
        trailerDayCost +
        trailerKmCost +
        dDriveCost +
        flightCost +
        ferryCost +
        tollCost;

    return RoundCalcResult(
      billableDays: billableDays,
      totalKm: totalKm,
      includedKm: includedKm,
      extraKm: extraKm,
      dDriveDays: dDriveDays,
      flightTickets: flightTickets,
      dayCost: dayCost,
      extraKmCost: extraKmCost,
      trailerDayCost: trailerDayCost,
      trailerKmCost: trailerKmCost,
      dDriveCost: dDriveCost,
      flightCost: flightCost,
      ferryCost: ferryCost,
      tollCost: tollCost,
      totalCost: totalCost,
      legKm: legKm,
    );
  }
}