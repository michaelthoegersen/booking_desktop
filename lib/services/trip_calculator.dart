import '../models/app_settings.dart';
import '../models/round_calc_result.dart';
import '../models/ferry_definition.dart';
import 'ferry_resolver.dart';

class TripCalculator {

  static RoundCalcResult calculateRound({
    required AppSettings settings,
    required List<DateTime> dates,
    required bool pickupEveningFirstDay,
    required bool trailer,
    required double totalKm,
    required List<double> legKm,

    // 🔥 NYTT – ferry-definisjoner fra settings / DB
    required List<FerryDefinition> ferries,

    required List<double> tollPerLeg,
    required List<String> extraPerLeg,
    required List<bool> hasTravelBefore,
  }) {
    final int entryCount = legKm.length;

    if (entryCount == 0 ||
        hasTravelBefore.length != entryCount ||
        tollPerLeg.length != entryCount ||
        extraPerLeg.length != entryCount) {
      return _emptyResult();
    }

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

    // ----------------------------------------
    // KM
    // ----------------------------------------

    final double includedKm =
        billableDays * settings.includedKmPerDay;

    final double extraKm =
        (totalKm - includedKm).clamp(0.0, double.infinity);

    // ----------------------------------------
    // BASE COSTS
    // ----------------------------------------

    final double dayCost =
        billableDays * settings.dayPrice;

    final double extraKmCost =
        extraKm * settings.extraKmPrice;

    // ----------------------------------------
    // D.DRIVE LOGIC
    // ----------------------------------------

    final double threshold = settings.dDriveKmThreshold;
    final double hardLimit = threshold * 2;

    final Map<String, List<int>> dayToIndexes = {};

    for (int i = 0; i < entryCount; i++) {
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

    final int baseDDriveDays =
        dayKm.values.where((v) => v >= threshold).length;

    int extraDays = 0;
    int flightTickets = 0;

    for (final c in clusters) {
      if (c.first != 0) {
        extraDays++;
        flightTickets++;
      }
      if (c.last != entryCount - 1) {
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
    // ✅ FERRY – AUTO MATCH FRA extraPerLeg
    // ----------------------------------------

    final double ferryCost =
        FerryResolver.resolveTotalFerryCost(
          extraPerLeg: extraPerLeg,
          ferries: ferries,
          trailer: trailer,
        );

    // ----------------------------------------
    // ✅ TOLL – FAST MODELL
    // ----------------------------------------

    final double tollCost = totalKm * 2.8;

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