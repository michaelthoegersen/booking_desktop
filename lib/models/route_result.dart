class RouteResult {
  final String id;
  final String from;
  final String to;
  final double km;
  final double ferry;
  final double toll;
  final String extra;

  RouteResult({
    required this.id,
    required this.from,
    required this.to,
    required this.km,
    required this.ferry,
    required this.toll,
    required this.extra,
  });

  factory RouteResult.fromMap(Map<String, dynamic> map) {
    return RouteResult(
      id: map['id'].toString(),
      from: map['from_place'] ?? '',
      to: map['to_place'] ?? '',
      km: (map['distance_total_km'] ?? 0).toDouble(),
      ferry: (map['ferry_price'] ?? 0).toDouble(),
      toll: (map['toll_nightliner'] ?? 0).toDouble(),
      extra: map['extra'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'from_place': from,
      'to_place': to,
      'distance_total_km': km,
      'ferry_price': ferry,
      'toll_nightliner': toll,
      'extra': extra,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  RouteResult copyWith({
    String? id,
    String? from,
    String? to,
    double? km,
    double? ferry,
    double? toll,
    String? extra,
  }) {
    return RouteResult(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      km: km ?? this.km,
      ferry: ferry ?? this.ferry,
      toll: toll ?? this.toll,
      extra: extra ?? this.extra,
    );
  }
}