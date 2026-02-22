import '../models/swe_settings.dart';
import '../models/swe_calc_result.dart';

/// Swedish per-leg price calculator.
///
/// Formula per leg (mirrors Excel "Calc-Present"):
///   base = ROUND(vehicle + km*kmPris + driver + dd + extra, -1)
///   legTotal = base + trailer + international
///
/// Round final total UP to nearest 1 000 SEK.
class SweCalculator {
  static const bool debug = true;

  static void _log(String msg) {
    if (debug) print('[SWE] $msg');
  }

  /// Calculate pricing for one round (set of legs).
  ///
  /// [legKm]           — km for each leg
  /// [dates]           — date for each leg (used for same-day deduplication)
  /// [trailer]         — trailer on this round (same for all legs)
  /// [utlTraktPerLeg]  — number of international allowances per leg (0 or more)
  /// [extraPerLeg]     — manual extra cost per leg (SEK)
  /// [pickupEveningFirstDay] — first unique date is a transit night, skip
  ///                           vehicle/driver for all legs on that date.
  ///
  /// Vehicle + driver daily rates are charged once per unique date.
  /// If two entries share the same date (e.g. last show + return home),
  /// only the first leg of that date carries the daily rate.
  static SweCalcResult calculateRound({
    required SweSettings settings,
    required List<double> legKm,
    List<DateTime>? dates,
    bool trailer = false,
    List<int>? utlTraktPerLeg,
    List<double>? extraPerLeg,
    bool pickupEveningFirstDay = false,
  }) {
    final int n = legKm.length;

    final List<double> vehicleCosts = [];
    final List<double> kmCosts = [];
    final List<double> driverCosts = [];
    final List<double> ddCosts = [];
    final List<double> extraCosts = [];
    final List<double> trailerCosts = [];
    final List<double> intlCosts = [];
    final List<double> totals = [];

    final double vehicle = settings.fordonDagpris;
    final double driver = settings.chaufforDagpris;
    final double ddDay = settings.ddDagpris;
    final double milpris = settings.milpris;
    final double trailerDag = settings.trailerhyraPerDygn;
    final double utlTrakt = settings.utlandstraktamente;

    // Build set of unique date strings in order of first appearance.
    // Index → date key (yyyy-MM-dd).
    final List<String> dateKeys = List.generate(n, (i) {
      if (dates != null && i < dates.length) {
        final d = dates[i];
        return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      }
      return '$i'; // fallback: treat each leg as its own "date"
    });

    // Determine which dates are billable (not the pickup-evening date).
    // The first unique date is the pickup-evening date when pickupEveningFirstDay.
    final String? pickupEveDate = pickupEveningFirstDay && dateKeys.isNotEmpty
        ? dateKeys[0]
        : null;

    // Track which dates have already had the daily rate charged.
    final Set<String> chargedDates = {};

    _log('--- START SWE ROUND CALC ---');
    _log('Fordon/dag: ${vehicle.toStringAsFixed(0)}');
    _log('Chauffor/dag: ${driver.toStringAsFixed(0)}');
    _log('DD/dag: ${ddDay.toStringAsFixed(0)}');
    _log('Milpris: ${milpris.toStringAsFixed(2)}');
    _log('pickupEvening: $pickupEveningFirstDay  pickupEveDate: $pickupEveDate');

    for (int i = 0; i < n; i++) {
      final km = legKm[i];
      final extra = (extraPerLeg != null && i < extraPerLeg.length)
          ? extraPerLeg[i]
          : 0.0;
      final utl = (utlTraktPerLeg != null && i < utlTraktPerLeg.length)
          ? utlTraktPerLeg[i]
          : 0;

      final dateKey = dateKeys[i];
      final bool isPickupEveDay = dateKey == pickupEveDate;
      // Charge daily rate only for the first leg of each billable date.
      final bool firstLegOfDate = !chargedDates.contains(dateKey);
      final bool chargeDaily = !isPickupEveDay && firstLegOfDate;
      if (firstLegOfDate) chargedDates.add(dateKey);

      final kmCost = km * settings.kmPrisPerKm;
      final vCost  = chargeDaily ? vehicle : 0.0;
      final dCost  = chargeDaily ? driver  : 0.0;
      final ddCost = chargeDaily && km > settings.ddKmGrans ? ddDay : 0.0;
      final trCost = trailer ? trailerDag : 0.0;
      final intCost = utl * utlTrakt;

      // ROUND to nearest 10 (Excel: ROUND(x, -1))
      final base = _roundToNearest(vCost + kmCost + dCost + ddCost + extra, 10);
      final legTotal = base + trCost + intCost;

      final tag = isPickupEveDay
          ? ' [pickup-eve]'
          : (!chargeDaily && !isPickupEveDay ? ' [same-date]' : '');
      _log(
        'Leg $i$tag [$dateKey]'
        ': km=$km  vehicle=${vCost.toStringAsFixed(0)}'
        '  km_cost=${kmCost.toStringAsFixed(0)}'
        '  driver=${dCost.toStringAsFixed(0)}'
        '  dd=${ddCost.toStringAsFixed(0)}'
        '  extra=${extra.toStringAsFixed(0)}'
        '  base=$base  trailer=${trCost.toStringAsFixed(0)}'
        '  intl=${intCost.toStringAsFixed(0)}'
        '  total=$legTotal',
      );

      vehicleCosts.add(vCost);
      kmCosts.add(kmCost);
      driverCosts.add(dCost);
      ddCosts.add(ddCost);
      extraCosts.add(extra);
      trailerCosts.add(trCost);
      intlCosts.add(intCost);
      totals.add(legTotal);
    }

    final double sumBeforeRound = totals.fold(0.0, (s, v) => s + v);

    // ROUNDUP to nearest 1 000 SEK
    final double totalCost = _roundUp(sumBeforeRound, 1000);

    _log('Sum before round: ${sumBeforeRound.toStringAsFixed(0)}');
    _log('Total (rounded up to 1000): ${totalCost.toStringAsFixed(0)}');
    _log('--- END SWE ROUND CALC ---');

    return SweCalcResult(
      legKm: List<double>.from(legKm),
      legVehicleCost: vehicleCosts,
      legKmCost: kmCosts,
      legDriverCost: driverCosts,
      legDdCost: ddCosts,
      legExtraCost: extraCosts,
      legTrailerCost: trailerCosts,
      legInternationalCost: intlCosts,
      legTotal: totals,
      totalCost: totalCost,
      vehicleDagpris: vehicle,
      chaufforDagpris: driver,
      ddDagpris: ddDay,
      milpris: milpris,
    );
  }

  // ===================================================
  // HELPERS
  // ===================================================

  /// ROUND(value, -1) — round to nearest [nearest].
  static double _roundToNearest(double value, int nearest) {
    if (nearest <= 0) return value;
    return (value / nearest).round() * nearest.toDouble();
  }

  /// ROUNDUP(value, -3) — round UP to nearest [nearest].
  static double _roundUp(double value, int nearest) {
    if (nearest <= 0) return value;
    return (value / nearest).ceil() * nearest.toDouble();
  }
}
