enum BusType {
  sleeper12,
  sleeper14,
  sleeper16,
  sleeper18,
  sleeper12StarRoom,
}

extension BusTypeLabel on BusType {
  String get label {
    switch (this) {
      case BusType.sleeper12:
        return "12-sleeper";
      case BusType.sleeper14:
        return "14-sleeper";
      case BusType.sleeper16:
        return "16-sleeper";
      case BusType.sleeper18:
        return "18-sleeper";
      case BusType.sleeper12StarRoom:
        return "12-sleeper + Star room";
    }
  }
}

class OfferDraft {
  String company;
  String contact;
  String production;

  // ✅ NEW (for PDF etc.)
  int busCount;
  BusType busType;

  final List<OfferRound> rounds;

  OfferDraft({
    this.company = '',
    this.contact = '',
    this.production = '',
    this.busCount = 1,
    this.busType = BusType.sleeper12,
  }) : rounds = List.generate(12, (_) => OfferRound());

  int get usedRounds =>
      rounds.where((r) => r.entries.isNotEmpty || r.startLocation.trim().isNotEmpty).length;

  int get totalDays => rounds.fold<int>(0, (sum, r) => sum + r.billableDays);

  double get totalKm => rounds.fold<double>(0, (sum, r) => sum + r.totalKm);
}

class OfferRound {
  String startLocation = '';

  /// checkbox per round
  bool trailer = false;

  /// pickup evening applies only for first entry
  bool pickupEveningFirstDay = false;

  final List<RoundEntry> entries = [];

  /// computed by ui/calculator
  double totalKm = 0;

  /// Billable days:
  /// - entries count
  /// - minus 1 if pickup evening + at least 1 entry
  int get billableDays {
    if (entries.isEmpty) return 0;
    final base = entries.length;
    if (pickupEveningFirstDay) return (base - 1).clamp(0, 999999);
    return base;
  }
}

class RoundEntry {
  final DateTime date;
  final String location;

  // ✅ NEW: ferry/bridge info from Supabase column "extra"
  final String extra;

  RoundEntry({
    required this.date,
    required this.location,
    this.extra = '',
  });

  RoundEntry copyWith({
    DateTime? date,
    String? location,
    String? extra,
  }) {
    return RoundEntry(
      date: date ?? this.date,
      location: location ?? this.location,
      extra: extra ?? this.extra,
    );
  }
}