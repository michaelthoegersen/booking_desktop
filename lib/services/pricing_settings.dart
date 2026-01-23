class PricingSettings {
  final double dayPrice;
  final int includedKmPerDay;
  final double extraKmPrice;

  final double trailerDayPrice;
  final double trailerKmPrice;

  const PricingSettings({
    required this.dayPrice,
    required this.includedKmPerDay,
    required this.extraKmPrice,
    required this.trailerDayPrice,
    required this.trailerKmPrice,
  });

  PricingSettings copyWith({
    double? dayPrice,
    int? includedKmPerDay,
    double? extraKmPrice,
    double? trailerDayPrice,
    double? trailerKmPrice,
  }) {
    return PricingSettings(
      dayPrice: dayPrice ?? this.dayPrice,
      includedKmPerDay: includedKmPerDay ?? this.includedKmPerDay,
      extraKmPrice: extraKmPrice ?? this.extraKmPrice,
      trailerDayPrice: trailerDayPrice ?? this.trailerDayPrice,
      trailerKmPrice: trailerKmPrice ?? this.trailerKmPrice,
    );
  }
}

/// ✅ defaults (senere flyttes til Settings/Supabase)
const defaultPricing = PricingSettings(
  dayPrice: 0, // du setter senere
  includedKmPerDay: 300,
  extraKmPrice: 20,
  trailerDayPrice: 0, // du setter senere
  trailerKmPrice: 2,
);