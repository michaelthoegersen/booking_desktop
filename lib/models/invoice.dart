class InvoiceRound {
  final DateTime startDate;
  final DateTime endDate;
  final double totalCost;
  final String label; // e.g. "Round 1"

  InvoiceRound({
    required this.startDate,
    required this.endDate,
    required this.totalCost,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'start': startDate.toIso8601String(),
        'end': endDate.toIso8601String(),
        'cost': totalCost,
        'label': label,
      };

  factory InvoiceRound.fromJson(Map<String, dynamic> json) => InvoiceRound(
        startDate: DateTime.parse(json['start'] as String),
        endDate: DateTime.parse(json['end'] as String),
        totalCost: (json['cost'] as num).toDouble(),
        label: json['label'] as String,
      );
}

class Invoice {
  String? id;
  String invoiceNumber; // "2025-001"
  DateTime invoiceDate;
  DateTime dueDate;

  String company;
  String contact;
  String phone;
  String email;
  String production;

  List<InvoiceRound> rounds;

  double totalExclVat;
  Map<String, double> vatBreakdown; // {"DK": 1234.0}
  double totalInclVat;
  Map<String, double> countryKm; // for VAT reference

  String bankAccount;
  String paymentRef;

  String status; // unpaid | paid | cancelled
  String? offerId;
  String? userId;
  DateTime? createdAt;

  Invoice({
    this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    this.company = '',
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.production = '',
    List<InvoiceRound>? rounds,
    this.totalExclVat = 0,
    Map<String, double>? vatBreakdown,
    this.totalInclVat = 0,
    Map<String, double>? countryKm,
    this.bankAccount = '',
    this.paymentRef = '',
    this.status = 'unpaid',
    this.offerId,
    this.userId,
    this.createdAt,
  })  : rounds = rounds ?? [],
        vatBreakdown = vatBreakdown ?? {},
        countryKm = countryKm ?? {};

  Map<String, dynamic> toJson() => {
        'invoice_number': invoiceNumber,
        'invoice_date': invoiceDate.toIso8601String().split('T').first,
        'due_date': dueDate.toIso8601String().split('T').first,
        'company': company,
        'contact': contact,
        'phone': phone,
        'email': email,
        'production': production,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'total_excl_vat': totalExclVat,
        'vat_breakdown': vatBreakdown,
        'total_incl_vat': totalInclVat,
        'country_km': countryKm,
        'bank_account': bankAccount,
        'payment_ref': paymentRef,
        'status': status,
        'offer_id': offerId,
        'user_id': userId,
      };

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final roundsRaw = json['rounds'] as List? ?? [];
    return Invoice(
      id: json['id'] as String?,
      invoiceNumber: json['invoice_number'] as String,
      invoiceDate: DateTime.parse(json['invoice_date'] as String),
      dueDate: DateTime.parse(json['due_date'] as String),
      company: json['company'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      production: json['production'] as String? ?? '',
      rounds: roundsRaw
          .map((r) => InvoiceRound.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
      totalExclVat: (json['total_excl_vat'] as num? ?? 0).toDouble(),
      vatBreakdown: json['vat_breakdown'] != null
          ? Map<String, double>.from(
              (json['vat_breakdown'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
              ),
            )
          : {},
      totalInclVat: (json['total_incl_vat'] as num? ?? 0).toDouble(),
      countryKm: json['country_km'] != null
          ? Map<String, double>.from(
              (json['country_km'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
              ),
            )
          : {},
      bankAccount: json['bank_account'] as String? ?? '',
      paymentRef: json['payment_ref'] as String? ?? '',
      status: json['status'] as String? ?? 'unpaid',
      offerId: json['offer_id'] as String?,
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
