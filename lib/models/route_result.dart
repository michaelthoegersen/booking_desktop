class RouteResult {
  final String id;
  final String from;
  final String to;
  final double km;
  final int durationMin;
  final String summary;

  RouteResult({
    required this.id,
    required this.from,
    required this.to,
    required this.km,
    required this.durationMin,
    required this.summary,
  });

  // ----------------------------
  // FROM SUPABASE MAP
  // ----------------------------
  factory RouteResult.fromMap(Map<String, dynamic> map) {
    return RouteResult(
      id: map['id'].toString(),

      from: map['from_place'] ?? '',
      to: map['to_place'] ?? '',

      km: (map['distance_total_km'] as num?)?.toDouble() ?? 0,

      durationMin: map['duration_min'] ?? 0,

      summary: map['extra'] ?? '',
    );
  }

  // ----------------------------
  // TO JSON (FOR UPDATE)
  // ----------------------------
  Map<String, dynamic> toJson() {
    return {
      'from_place': from,
      'to_place': to,
      'distance_total_km': km,
      'duration_min': durationMin,
      'extra': summary,
    };
  }

  RouteResult copyWith({
    String? id,
    String? from,
    String? to,
    double? km,
    int? durationMin,
    String? summary,
  }) {
    return RouteResult(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      km: km ?? this.km,
      durationMin: durationMin ?? this.durationMin,
      summary: summary ?? this.summary,
    );
  }
}