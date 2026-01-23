class DDriveFlightResult {
  final int dDriveDays;
  final int flightTickets;

  const DDriveFlightResult({
    required this.dDriveDays,
    required this.flightTickets,
  });
}

/// Rules:
/// - D.Drive counted per leg where km > threshold
/// - Consecutive D.Drive days sum
/// - If there is a gap (non-ddrive between ddrive clusters):
///   add +1 day before and +1 after AND +1 flight before and +1 after
/// - Exception:
///   - if round starts with ddrive: no day-before and no flight-before
///   - if round ends with ddrive: no day-after and no flight-after
class DDriveFlightLogic {
  static DDriveFlightResult calculate({
    required List<double> kmPerLegSorted,
    required double threshold,
  }) {
    if (kmPerLegSorted.isEmpty) return const DDriveFlightResult(dDriveDays: 0, flightTickets: 0);

    final isDD = kmPerLegSorted.map((km) => km > threshold).toList();

    int dDriveDays = isDD.where((x) => x).length;
    int flightTickets = 0;

    // find clusters of DDrive
    final clusters = <List<int>>[];
    List<int>? current;

    for (int i = 0; i < isDD.length; i++) {
      if (isDD[i]) {
        current ??= [];
        current.add(i);
      } else {
        if (current != null) {
          clusters.add(current);
          current = null;
        }
      }
    }
    if (current != null) clusters.add(current);

    if (clusters.isEmpty) return const DDriveFlightResult(dDriveDays: 0, flightTickets: 0);

    for (final cluster in clusters) {
      final startsAt0 = cluster.first == 0;
      final endsAtLast = cluster.last == isDD.length - 1;

      // if cluster is not at start -> add day before + flight before
      if (!startsAt0) {
        dDriveDays += 1;
        flightTickets += 1;
      }

      // if cluster is not at end -> add day after + flight after
      if (!endsAtLast) {
        dDriveDays += 1;
        flightTickets += 1;
      }
    }

    return DDriveFlightResult(
      dDriveDays: dDriveDays,
      flightTickets: flightTickets,
    );
  }
}