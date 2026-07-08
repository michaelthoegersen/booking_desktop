class CompanyBranding {
  final String? id;
  final String companyId;
  final String? logoUrl;
  final String? companyName;
  final String? addressLine;
  final String? contactLine1;
  final String? contactLine2;
  final String? signatureName;
  final String? termsText;
  final Map<String, String> termsTranslations;

  CompanyBranding({
    this.id,
    required this.companyId,
    this.logoUrl,
    this.companyName,
    this.addressLine,
    this.contactLine1,
    this.contactLine2,
    this.signatureName,
    this.termsText,
    this.termsTranslations = const {},
  });

  factory CompanyBranding.fromJson(Map<String, dynamic> json) {
    final raw = json['terms_translations'];
    final translations = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is String) translations[k.toString()] = v;
      });
    }

    return CompanyBranding(
      id: json['id'] as String?,
      companyId: json['company_id'] as String,
      logoUrl: json['logo_url'] as String?,
      companyName: json['company_name'] as String?,
      addressLine: json['address_line'] as String?,
      contactLine1: json['contact_line_1'] as String?,
      contactLine2: json['contact_line_2'] as String?,
      signatureName: json['signature_name'] as String?,
      termsText: json['terms_text'] as String?,
      termsTranslations: translations,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'logo_url': logoUrl,
        'company_name': companyName,
        'address_line': addressLine,
        'contact_line_1': contactLine1,
        'contact_line_2': contactLine2,
        'signature_name': signatureName,
        'terms_text': termsText,
        'terms_translations': termsTranslations,
        'updated_at': DateTime.now().toIso8601String(),
      };

  /// Returns terms text for the requested language code.
  /// Falls back to the Norwegian source when no translation exists.
  String? termsFor(String languageCode) {
    final code = languageCode.toLowerCase();
    if (code == 'no' || code == 'nb') return termsText;
    final translated = termsTranslations[code];
    if (translated != null && translated.trim().isNotEmpty) {
      return translated;
    }
    return termsText;
  }

  CompanyBranding copyWith({
    String? logoUrl,
    String? companyName,
    String? addressLine,
    String? contactLine1,
    String? contactLine2,
    String? signatureName,
    String? termsText,
    Map<String, String>? termsTranslations,
  }) {
    return CompanyBranding(
      id: id,
      companyId: companyId,
      logoUrl: logoUrl ?? this.logoUrl,
      companyName: companyName ?? this.companyName,
      addressLine: addressLine ?? this.addressLine,
      contactLine1: contactLine1 ?? this.contactLine1,
      contactLine2: contactLine2 ?? this.contactLine2,
      signatureName: signatureName ?? this.signatureName,
      termsText: termsText ?? this.termsText,
      termsTranslations: termsTranslations ?? this.termsTranslations,
    );
  }
}
