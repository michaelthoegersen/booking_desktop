import 'dart:convert';
import 'package:http/http.dart' as http;

/// Data class for a Brreg company result.
class BrregCompany {
  final String orgNr;
  final String name;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? country;

  const BrregCompany({
    required this.orgNr,
    required this.name,
    this.address,
    this.postalCode,
    this.city,
    this.country,
  });

  factory BrregCompany.fromJson(Map<String, dynamic> json) {
    // Prefer forretningsadresse, fall back to postadresse
    final addr = json['forretningsadresse'] as Map<String, dynamic>?
        ?? json['postadresse'] as Map<String, dynamic>?;

    final addrLines = addr?['adresse'] as List<dynamic>?;

    return BrregCompany(
      orgNr: json['organisasjonsnummer'].toString(),
      name: json['navn'] as String? ?? '',
      address: addrLines != null && addrLines.isNotEmpty
          ? addrLines.join(', ')
          : null,
      postalCode: addr?['postnummer'] as String?,
      city: addr?['poststed'] as String?,
      country: addr?['land'] as String?,
    );
  }
}

/// Service for searching the Norwegian Enhetsregisteret (Brreg) API.
class BrregService {
  static const _base = 'https://data.brreg.no/enhetsregisteret/api';

  /// Search companies by name. Returns up to [size] results.
  static Future<List<BrregCompany>> search(String query,
      {int size = 15}) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_base/enheter')
        .replace(queryParameters: {'navn': query.trim(), 'size': '$size'});
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return [];

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final embedded = body['_embedded'] as Map<String, dynamic>?;
    if (embedded == null) return [];

    final units = embedded['enheter'] as List<dynamic>? ?? [];
    return units
        .map((e) => BrregCompany.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Look up a single company by org number.
  static Future<BrregCompany?> lookup(String orgNr) async {
    final cleaned = orgNr.replaceAll(RegExp(r'\s'), '');
    if (cleaned.length != 9) return null;

    final uri = Uri.parse('$_base/enheter/$cleaned');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return BrregCompany.fromJson(body);
  }
}
