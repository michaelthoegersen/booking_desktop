/// Result of the Swedish per-leg pricing calculation.
class SweCalcResult {
  // ===================================================
  // PER-LEG BREAKDOWN
  // ===================================================
  final List<double> legKm;
  final List<double> legVehicleCost;
  final List<double> legKmCost;
  final List<double> legDriverCost;
  final List<double> legDdCost;
  final List<double> legExtraCost;
  final List<double> legTrailerCost;
  final List<double> legInternationalCost;

  /// Per-leg total after rounding to nearest 10 + trailer + international.
  final List<double> legTotal;

  // ===================================================
  // TOTALS
  // ===================================================

  /// Sum of all legTotal values, rounded UP to nearest 1 000 SEK.
  final double totalCost;

  // ===================================================
  // COMPUTED PRICES USED (for display in UI)
  // ===================================================
  final double vehicleDagpris;
  final double chaufforDagpris;
  final double ddDagpris;
  final double milpris; // per mil (10 km)

  const SweCalcResult({
    required this.legKm,
    required this.legVehicleCost,
    required this.legKmCost,
    required this.legDriverCost,
    required this.legDdCost,
    required this.legExtraCost,
    required this.legTrailerCost,
    required this.legInternationalCost,
    required this.legTotal,
    required this.totalCost,
    required this.vehicleDagpris,
    required this.chaufforDagpris,
    required this.ddDagpris,
    required this.milpris,
  });
}
