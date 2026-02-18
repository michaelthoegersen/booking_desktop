// ============================================================
// BUS TYPE
// ============================================================

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

// ============================================================
// OFFER DRAFT
// ============================================================

class OfferDraft {
  String? userId;

  String company;
  String contact;
  // ✅ NYE
  String phone;
  String email;
  String production;

  /// ✅ GLOBAL STATUS
  String status;

  int busCount;
  BusType busType;

  /// ✅ Saved bus
  String? bus;

  final List<OfferRound> rounds;

  OfferDraft({
    this.userId,
    this.company = '',
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.production = '',
    this.status = 'Draft',
    this.busCount = 1,
    this.busType = BusType.sleeper12,
    this.bus,
  }) : rounds = List.generate(12, (_) => OfferRound());

  // ------------------------------------------------------------
  // STATUS SAFETY
  // ------------------------------------------------------------

  static const List<String> _allowedStatus = [
    'Draft',
    'Inquiry',
    'Confirmed',
    'Cancelled',
  ];

  static String _safeStatus(String? value) {
    if (value == null) return 'Draft';
    if (_allowedStatus.contains(value)) return value;
    return 'Draft';
  }

  // ------------------------------------------------------------
  // COMPUTED
  // ------------------------------------------------------------

  int get usedRounds => rounds.where(
        (r) =>
            r.entries.isNotEmpty ||
            r.startLocation.trim().isNotEmpty,
      ).length;

  int get totalDays =>
      rounds.fold<int>(0, (sum, r) => sum + r.billableDays);

  double get totalKm =>
      rounds.fold<double>(0, (sum, r) => sum + r.totalKm);

  // ------------------------------------------------------------
  // JSON
  // ------------------------------------------------------------

  Map<String, dynamic> toJson() {
  return {
    'userId': userId,
    'company': company,
    'contact': contact,

    // ✅ LEGG TIL DISSE
    'phone': phone,
    'email': email,

    'production': production,

    // ✅ SAFE STATUS
    'status': _safeStatus(status),

    'busCount': busCount,
    'busType': busType.name,
    'bus': bus,

    'rounds': rounds.map((r) => r.toJson()).toList(),
  };
}


  static OfferDraft fromJson(Map<String, dynamic> json) {
    final draft = OfferDraft(
      userId: json['userId'] as String?,

      company: (json['company'] ?? '') as String,
      contact: (json['contact'] ?? '') as String,
      // ✅
      phone: (json['phone'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      production: (json['production'] ?? '') as String,

      // ✅ SAFE LOAD
      status: _safeStatus(json['status'] as String?),

      busCount: (json['busCount'] ?? 1) as int,

      busType: _busTypeFromName(
        (json['busType'] ?? 'sleeper12') as String,
      ),

      bus: json['bus'] as String?,
    );

    final rawRounds = (json['rounds'] as List?) ?? [];

    final max = rawRounds.length < draft.rounds.length
        ? rawRounds.length
        : draft.rounds.length;

    for (int i = 0; i < max; i++) {
      draft.rounds[i] = OfferRound.fromJson(
        Map<String, dynamic>.from(rawRounds[i]),
      );
    }

    return draft;
  }

  static BusType _busTypeFromName(String name) {
    for (final t in BusType.values) {
      if (t.name == name) return t;
    }
    return BusType.sleeper12;
  }
  // ------------------------------------------------------------
// COPY WITH SELECTED ROUNDS (FOR PDF PAGING)
// ------------------------------------------------------------
OfferDraft copyWithRounds(List<int> indexes) {
  final draft = OfferDraft(
    userId: this.userId,

    company: this.company,
    contact: this.contact,
    phone: this.phone,
    email: this.email,
    production: this.production,

    status: this.status,

    busCount: this.busCount,
    busType: this.busType,
    bus: this.bus,
  );

  // Clear default rounds
  draft.rounds.clear();

  // Add only selected rounds
  for (final i in indexes) {
    if (i >= 0 && i < this.rounds.length) {
      draft.rounds.add(this.rounds[i]);
    }
  }

  return draft;
}
}

// ============================================================
// ROUND
// ============================================================

class OfferRound {
  String startLocation = '';
  bool trailer = false;
  bool pickupEveningFirstDay = false;

  // =========================================================
  // ⭐ LEGACY BUS (MÅ EKSISTERE – brukes av calendar/PDF)
  // =========================================================
  String? bus;

  // =========================================================
  // 🚌 ENTERPRISE MULTI BUS (NYTT)
  // =========================================================

  /// Slot 0 = Bus 1
  /// Slot 1 = Bus 2
  /// Slot 2 = Bus 3
  /// Slot 3 = Bus 4
  List<String?> busSlots = [null, null, null, null];

  /// Trailer per buss
  List<bool> trailerSlots = [false, false, false, false];

  // =========================================================

  final List<RoundEntry> entries = [];

  double totalKm = 0;

  int get billableDays {
    if (entries.isEmpty) return 0;

    final base = entries.length;

    if (pickupEveningFirstDay) {
      return (base - 1).clamp(0, 999999);
    }

    return base;
  }

  // ------------------------------------------------------------
  // JSON
  // ------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'startLocation': startLocation,
      'trailer': trailer,
      'pickupEveningFirstDay': pickupEveningFirstDay,

      // ⭐ LEGACY
      'bus': bus,

      // ⭐ ENTERPRISE
      'busSlots': busSlots,
      'trailerSlots': trailerSlots,

      'totalKm': totalKm,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  static OfferRound fromJson(Map<String, dynamic> json) {
    final r = OfferRound();

    r.startLocation = (json['startLocation'] ?? '') as String;

    r.trailer = (json['trailer'] ?? false) as bool;

    r.pickupEveningFirstDay =
        (json['pickupEveningFirstDay'] ?? false) as bool;

    // =====================================================
    // LEGACY LOAD
    // =====================================================
    r.bus = json['bus'] as String?;

    // =====================================================
    // ENTERPRISE LOAD (BAKOVERKOMPATIBEL)
    // =====================================================

    if (json['busSlots'] != null) {
      r.busSlots = List<String?>.from(json['busSlots']);
    } else {
      // fallback for gamle drafts
      r.busSlots[0] = r.bus;
    }

    if (json['trailerSlots'] != null) {
      r.trailerSlots = List<bool>.from(json['trailerSlots']);
    } else {
      r.trailerSlots[0] = r.trailer;
    }

    r.totalKm = ((json['totalKm'] ?? 0) as num).toDouble();

    final rawEntries = (json['entries'] as List?) ?? [];

    for (final raw in rawEntries) {
      r.entries.add(
        RoundEntry.fromJson(
          Map<String, dynamic>.from(raw),
        ),
      );
    }

    return r;
  }
}

// ============================================================
// ENTRY
// ============================================================

class RoundEntry {
  final DateTime date;
  final String location;
  final String extra;

  /// ✅ Country km breakdown (VAT etc)
  final Map<String, double> countryKm;

  RoundEntry({
    required this.date,
    required this.location,
    required this.extra,
    Map<String, double>? countryKm,
  }) : countryKm = countryKm ?? const {};

  RoundEntry copyWith({
    DateTime? date,
    String? location,
    String? extra,
    Map<String, double>? countryKm,
  }) {
    return RoundEntry(
      date: date ?? this.date,
      location: location ?? this.location,
      extra: extra ?? this.extra,
      countryKm: countryKm ?? this.countryKm,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'location': location,
      'extra': extra,

      // ✅ COUNTRY KM
      'countryKm': countryKm,
    };
  }

  factory RoundEntry.fromJson(Map<String, dynamic> json) {
    return RoundEntry(
      date: DateTime.parse(json['date']),

      location: (json['location'] ?? '') as String,

      extra: (json['extra'] ?? '') as String,

      countryKm: json['countryKm'] != null
          ? Map<String, double>.from(
              (json['countryKm'] as Map).map(
                (k, v) => MapEntry(
                  k.toString(),
                  (v as num).toDouble(),
                ),
              ),
            )
          : {},
    );
  }
}