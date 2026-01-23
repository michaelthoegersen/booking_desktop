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

  // ------------------------------------------------------------
  // ✅ JSON SUPPORT
  // ------------------------------------------------------------
  Map<String, dynamic> toJson() {
    return {
      'company': company,
      'contact': contact,
      'production': production,
      'busCount': busCount,
      'busType': busType.name,
      'rounds': rounds.map((r) => r.toJson()).toList(),
    };
  }

  static OfferDraft fromJson(Map<String, dynamic> json) {
    final draft = OfferDraft(
      company: (json['company'] ?? '') as String,
      contact: (json['contact'] ?? '') as String,
      production: (json['production'] ?? '') as String,
      busCount: (json['busCount'] ?? 1) as int,
      busType: _busTypeFromName((json['busType'] ?? 'sleeper12') as String),
    );

    final rawRounds = (json['rounds'] as List?) ?? [];
    final max = rawRounds.length < draft.rounds.length ? rawRounds.length : draft.rounds.length;

    for (int i = 0; i < max; i++) {
      draft.rounds[i] = OfferRound.fromJson(Map<String, dynamic>.from(rawRounds[i]));
    }

    return draft;
  }

  static BusType _busTypeFromName(String name) {
    for (final t in BusType.values) {
      if (t.name == name) return t;
    }
    return BusType.sleeper12;
  }
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

  // ------------------------------------------------------------
  // ✅ JSON SUPPORT
  // ------------------------------------------------------------
  Map<String, dynamic> toJson() {
    return {
      'startLocation': startLocation,
      'trailer': trailer,
      'pickupEveningFirstDay': pickupEveningFirstDay,
      'totalKm': totalKm,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  static OfferRound fromJson(Map<String, dynamic> json) {
    final r = OfferRound();
    r.startLocation = (json['startLocation'] ?? '') as String;
    r.trailer = (json['trailer'] ?? false) as bool;
    r.pickupEveningFirstDay = (json['pickupEveningFirstDay'] ?? false) as bool;
    r.totalKm = ((json['totalKm'] ?? 0) as num).toDouble();

    final rawEntries = (json['entries'] as List?) ?? [];
    for (final raw in rawEntries) {
      r.entries.add(RoundEntry.fromJson(Map<String, dynamic>.from(raw)));
    }

    return r;
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

  // ------------------------------------------------------------
  // ✅ JSON SUPPORT
  // ------------------------------------------------------------
  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'location': location,
      'extra': extra,
    };
  }

  static RoundEntry fromJson(Map<String, dynamic> json) {
    return RoundEntry(
      date: DateTime.parse(json['date'] as String),
      location: (json['location'] ?? '') as String,
      extra: (json['extra'] ?? '') as String,
    );
  }
}