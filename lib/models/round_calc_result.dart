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
  final double bridgeCost;
  final double tollCost;

  /// Swedish km (toll-free)
  final double sweKm;
  /// German km (toll-free)
  final double deKm;
  /// Km subject to toll (totalKm - sweKm - deKm)
  final double tollableKm;

  final List<double> tollPerLeg;
  final List<double> legKm;
  final List<String> extraPerLeg;
  final List<bool> hasTravelBefore;
  final List<bool> noDDrivePerLeg;

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
    this.bridgeCost = 0,
    required this.tollCost,
    this.sweKm = 0,
    this.deKm = 0,
    this.tollableKm = 0,
    required this.tollPerLeg,
    required this.legKm,
    required this.extraPerLeg,
    required this.hasTravelBefore,
    this.noDDrivePerLeg = const [],
    required this.totalCost,
  });
}