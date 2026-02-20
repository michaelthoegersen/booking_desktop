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
  /// [trailer]         — trailer on this round (same for all legs)
  /// [utlTraktPerLeg]  — number of international allowances per leg (0 or more)
  /// [extraPerLeg]     — manual extra cost per leg (SEK)
  static SweCalcResult calculateRound({
    required SweSettings settings,
    required List<double> legKm,
    bool trailer = false,
    List<int>? utlTraktPerLeg,
    List<double>? extraPerLeg,
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

    _log('--- START SWE ROUND CALC ---');
    _log('Fordon/dag: ${vehicle.toStringAsFixed(0)}');
    _log('Chauffor/dag: ${driver.toStringAsFixed(0)}');
    _log('DD/dag: ${ddDay.toStringAsFixed(0)}');
    _log('Milpris: ${milpris.toStringAsFixed(2)}');

    for (int i = 0; i < n; i++) {
      final km = legKm[i];
      final extra = (extraPerLeg != null && i < extraPerLeg.length)
          ? extraPerLeg[i]
          : 0.0;
      final utl = (utlTraktPerLeg != null && i < utlTraktPerLeg.length)
          ? utlTraktPerLeg[i]
          : 0;

      final kmCost = km * settings.kmPrisPerKm;
      final ddCost = km > settings.ddKmGrans ? ddDay : 0.0;
      final trCost = trailer ? trailerDag : 0.0;
      final intCost = utl * utlTrakt;

      // ROUND to nearest 10 (Excel: ROUND(x, -1))
      final base = _roundToNearest(vehicle + kmCost + driver + ddCost + extra, 10);
      final legTotal = base + trCost + intCost;

      _log(
        'Leg $i: km=$km  vehicle=${vehicle.toStringAsFixed(0)}'
        '  km_cost=${kmCost.toStringAsFixed(0)}'
        '  driver=${driver.toStringAsFixed(0)}'
        '  dd=${ddCost.toStringAsFixed(0)}'
        '  extra=${extra.toStringAsFixed(0)}'
        '  base=$base  trailer=${trCost.toStringAsFixed(0)}'
        '  intl=${intCost.toStringAsFixed(0)}'
        '  total=$legTotal',
      );

      vehicleCosts.add(vehicle);
      kmCosts.add(kmCost);
      driverCosts.add(driver);
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
