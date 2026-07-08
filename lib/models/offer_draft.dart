// ============================================================
// BUS TYPE — now a plain String, configurable per company.
// Legacy enum names are mapped to display labels for backwards compat.
// ============================================================

/// Maps legacy enum names (stored in existing offers) to display labels.
const _legacyBusTypeLabels = <String, String>{
  'sleeper12': '12-sleeper',
  'sleeper14': '14-sleeper',
  'sleeper16': '16-sleeper',
  'sleeper18': '18-sleeper',
  'sleeper12StarRoom': '12-sleeper + Star room',
  'conference': '20-50 seats',
};

/// Default vehicle categories used as fallback when DB is empty.
const defaultVehicleCategories = <String>[
  '12-sleeper',
  '14-sleeper',
  '16-sleeper',
  '18-sleeper',
  '12-sleeper + Star room',
  '20-50 seats',
];

/// Resolve a stored busType value to a display label.
/// Handles both legacy enum names and new plain-text names.
String busTypeLabel(String value) {
  return _legacyBusTypeLabels[value] ?? value;
}
// ============================================================
// PRICING OVERRIDE (DRAFT ONLY)
// ============================================================

class OfferPricingOverride {
  final double dayPrice;
  final double extraKmPrice;
  final double trailerDayPrice;
  final double trailerKmPrice;
  final double dDriveDayPrice;
  final double flightTicketPrice;

  const OfferPricingOverride({
    required this.dayPrice,
    required this.extraKmPrice,
    required this.trailerDayPrice,
    required this.trailerKmPrice,
    required this.dDriveDayPrice,
    required this.flightTicketPrice,
  });

  Map<String, dynamic> toJson() => {
        'dayPrice': dayPrice,
        'extraKmPrice': extraKmPrice,
        'trailerDayPrice': trailerDayPrice,
        'trailerKmPrice': trailerKmPrice,
        'dDriveDayPrice': dDriveDayPrice,
        'flightTicketPrice': flightTicketPrice,
      };

  factory OfferPricingOverride.fromJson(Map<String, dynamic> json) {
    return OfferPricingOverride(
      dayPrice: (json['dayPrice'] ?? 0).toDouble(),
      extraKmPrice: (json['extraKmPrice'] ?? 0).toDouble(),
      trailerDayPrice: (json['trailerDayPrice'] ?? 0).toDouble(),
      trailerKmPrice: (json['trailerKmPrice'] ?? 0).toDouble(),
      dDriveDayPrice: (json['dDriveDayPrice'] ?? 0).toDouble(),
      flightTicketPrice: (json['flightTicketPrice'] ?? 0).toDouble(),
    );
  }
    // ------------------------------------------------------------
  // COPY WITH
  // ------------------------------------------------------------
  OfferPricingOverride copyWith({
    double? dayPrice,
    double? extraKmPrice,
    double? trailerDayPrice,
    double? trailerKmPrice,
    double? dDriveDayPrice,
    double? flightTicketPrice,
  }) {
    return OfferPricingOverride(
      dayPrice: dayPrice ?? this.dayPrice,
      extraKmPrice: extraKmPrice ?? this.extraKmPrice,
      trailerDayPrice: trailerDayPrice ?? this.trailerDayPrice,
      trailerKmPrice: trailerKmPrice ?? this.trailerKmPrice,
      dDriveDayPrice: dDriveDayPrice ?? this.dDriveDayPrice,
      flightTicketPrice: flightTicketPrice ?? this.flightTicketPrice,
    );
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
  String busType;

  /// ✅ Saved bus
  String? bus;
OfferPricingOverride? pricingOverride;
  double? totalOverride;

  /// Per-round price overrides (round index → overridden total)
  Map<int, double?> roundOverrides;

  /// Pricing model: 'norsk' (Norwegian day-based) or 'svensk' (Swedish per-leg)
  String pricingModel;

  /// Output language for the offer PDF. Defaults to Norwegian.
  /// Supported: 'no', 'en', 'sv', 'de'.
  String language;

  final List<OfferRound> rounds;

  /// Global bus selection per slot — sets default for all rounds.
  /// Rounds with a different specific bus set are not overwritten.
  List<String?> globalBusSlots;

  OfferDraft({
    this.userId,
    this.company = '',
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.production = '',
    this.status = 'Draft',
    this.busCount = 1,
    this.busType = '12-sleeper',
    this.bus,
    this.pricingOverride,
    this.totalOverride,
    Map<int, double?>? roundOverrides,
    this.pricingModel = 'norsk',
    this.language = 'no',
  })  : roundOverrides = roundOverrides ?? {},
        rounds = List.generate(12, (_) => OfferRound()),
        globalBusSlots = List.generate(4, (_) => null);

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
    'busType': busType,
    'bus': bus,

    // ⭐⭐⭐ NYTT (pricing override)
    'pricingOverride': pricingOverride?.toJson(),

    // Pricing model ('norsk' / 'svensk')
    'pricingModel': pricingModel,

    // Output language for the PDF ('no' / 'en' / 'sv' / 'de')
    'language': language,

    // Per-round price overrides
    'roundOverrides': roundOverrides.map((k, v) => MapEntry(k.toString(), v)),

    'globalBusSlots': globalBusSlots,
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

    busType: busTypeLabel((json['busType'] ?? '12-sleeper') as String),

    bus: json['bus'] as String?,

    // ⭐⭐⭐ NYTT (pricing override)
    pricingOverride: json['pricingOverride'] != null
        ? OfferPricingOverride.fromJson(
            Map<String, dynamic>.from(json['pricingOverride']),
          )
        : null,

    // Pricing model (backwards compatible — default 'norsk')
    pricingModel: (json['pricingModel'] as String?) ?? 'norsk',

    // Output language (backwards compatible — default 'no')
    language: (json['language'] as String?) ?? 'no',

    // Per-round price overrides
    roundOverrides: _parseRoundOverrides(json['roundOverrides']),
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

  final rawGlobal = json['globalBusSlots'];
  if (rawGlobal != null) {
    draft.globalBusSlots = List<String?>.from(rawGlobal);
  }

  return draft;
}
  static Map<int, double?> _parseRoundOverrides(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    final result = <int, double?>{};
    for (final e in raw.entries) {
      final key = int.tryParse(e.key.toString());
      if (key == null) continue;
      if (e.value == null) {
        result[key] = null;
      } else {
        result[key] = (e.value as num).toDouble();
      }
    }
    return result;
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
    pricingModel: this.pricingModel,
    language: this.language,
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

  /// Ferry name per leg (index matches entries). Populated at calc time.
  List<String?> ferryPerLeg = [];

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
      'ferryPerLeg': ferryPerLeg,
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

    if (json['ferryPerLeg'] != null) {
      r.ferryPerLeg = List<String?>.from(json['ferryPerLeg']);
    }

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