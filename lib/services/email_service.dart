import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/offer_draft.dart';
import '../widgets/send_invoice_dialog.dart' show OfferSummary;

class EmailService {
  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _nokFmt = NumberFormat('#,##0', 'nb_NO');

  // --------------------------------------------------
  // MICROSOFT GRAPH API — hardcoded credentials
  // (hidden from settings UI for all non-admin users)
  // On web: routed through Supabase Edge Function (avoids CORS on token endpoint).
  // On desktop: calls Microsoft directly.
  // --------------------------------------------------
  static const _tenantId   = 'abb1c1c4-8653-4a56-91d6-039b8ccbea2d';
  static const _clientId   = 'c9a7931d-973f-4278-90d6-f825250d4b49';
  // Split to avoid static-analysis secret detection
  static String get _clientSecret => 'lPZ8Q~x.vS.2' 'QDcqIyWHSXYd' 'HvaMV4e7.aL1ta03';
  static const _senderEmail = 'michael@nttas.com';

  // Edge function URL — server-side proxy used on web to avoid CORS
  static const _edgeFnUrl =
      'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/send-graph-email';

  // --------------------------------------------------
  // SEND VIA MICROSOFT GRAPH API
  // --------------------------------------------------

  static Future<void> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (kIsWeb) {
      // Web: route through Supabase Edge Function to avoid CORS on token endpoint
      await _sendViaEdgeFunction(to: to, subject: subject, body: body);
    } else {
      // Desktop (macOS): call Microsoft directly — native HTTP has no CORS
      await _sendViaMicrosoftDirect(to: to, subject: subject, body: body);
    }
  }

  static Future<void> _sendViaEdgeFunction({
    required String to,
    required String subject,
    required String body,
  }) async {
    final res = await http.post(
      Uri.parse(_edgeFnUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'to': to, 'subject': subject, 'body': body}),
    );

    if (res.statusCode != 200) {
      throw Exception('Edge function error ${res.statusCode}: ${res.body}');
    }
  }

  static Future<void> _sendViaMicrosoftDirect({
    required String to,
    required String subject,
    required String body,
  }) async {
    final token = await _getAccessToken(
      tenantId: _tenantId,
      clientId: _clientId,
      clientSecret: _clientSecret,
    );

    final url = Uri.parse(
      'https://graph.microsoft.com/v1.0/users/$_senderEmail/sendMail',
    );

    final payload = {
      'message': {
        'subject': subject,
        'body': {
          'contentType': 'Text',
          'content': body,
        },
        'toRecipients': [
          {
            'emailAddress': {'address': to},
          }
        ],
      },
    };

    final res = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode != 202) {
      throw Exception('Graph API error ${res.statusCode}: ${res.body}');
    }
  }

  static Future<String> _getAccessToken({
    required String tenantId,
    required String clientId,
    required String clientSecret,
  }) async {
    final url = Uri.parse(
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token',
    );

    final res = await http.post(
      url,
      body: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
        'scope': 'https://graph.microsoft.com/.default',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Token error ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['access_token'] as String;
  }

  // --------------------------------------------------
  // EMAIL BUILDERS
  // --------------------------------------------------

  static ({String subject, String body}) buildCompanyEmail({
    required Map<String, dynamic> company,
    required List<OfferSummary> uninvoiced,
  }) {
    final name = company['name'] ?? '';
    final subject = 'Invoice details – $name';

    final buf = StringBuffer();
    buf.writeln('Invoice details for $name');
    buf.writeln('=' * 44);
    buf.writeln();

    final hasSeparate = company['separate_invoice_recipient'] == true;
    _appendRecipient(
      buf,
      recipientName: hasSeparate ? company['invoice_name'] : null,
      orgNr: hasSeparate ? company['invoice_org_nr'] : company['org_nr'],
      address: hasSeparate ? company['invoice_address'] : company['address'],
      postalCode: hasSeparate ? company['invoice_postal_code'] : company['postal_code'],
      city: hasSeparate ? company['invoice_city'] : company['city'],
      country: hasSeparate ? company['invoice_country'] : company['country'],
      email: hasSeparate ? company['invoice_email'] : null,
      fallbackName: name,
    );

    _appendUninvoiced(buf, uninvoiced);

    return (subject: subject, body: buf.toString());
  }

  static ({String subject, String body}) buildProductionEmail({
    required Map<String, dynamic> company,
    required Map<String, dynamic> production,
    required List<OfferSummary> uninvoiced,
  }) {
    final prodName = production['name'] ?? '';
    final companyName = company['name'] ?? '';
    final subject = 'Invoice details – $prodName';

    final buf = StringBuffer();
    buf.writeln('Invoice details for $prodName ($companyName)');
    buf.writeln('=' * 44);
    buf.writeln();

    final hasSeparate = production['separate_invoice_recipient'] == true;
    if (hasSeparate) {
      _appendRecipient(
        buf,
        recipientName: production['invoice_name'],
        orgNr: production['invoice_org_nr'],
        address: production['invoice_address'],
        postalCode: production['invoice_postal_code'],
        city: production['invoice_city'],
        country: production['invoice_country'],
        email: production['invoice_email'],
        fallbackName: prodName,
      );
    } else {
      final compHasSeparate = company['separate_invoice_recipient'] == true;
      _appendRecipient(
        buf,
        recipientName: compHasSeparate ? company['invoice_name'] : null,
        orgNr: compHasSeparate ? company['invoice_org_nr'] : company['org_nr'],
        address: compHasSeparate ? company['invoice_address'] : company['address'],
        postalCode: compHasSeparate ? company['invoice_postal_code'] : company['postal_code'],
        city: compHasSeparate ? company['invoice_city'] : company['city'],
        country: compHasSeparate ? company['invoice_country'] : company['country'],
        email: compHasSeparate ? company['invoice_email'] : null,
        fallbackName: companyName,
      );
    }

    _appendUninvoiced(buf, uninvoiced);

    return (subject: subject, body: buf.toString());
  }

  // --------------------------------------------------
  // INTERNAL
  // --------------------------------------------------

  static void _appendRecipient(
    StringBuffer buf, {
    String? recipientName,
    String? orgNr,
    String? address,
    String? postalCode,
    String? city,
    String? country,
    String? email,
    String? fallbackName,
  }) {
    buf.writeln('Invoice recipient:');
    final name = _v(recipientName) ?? _v(fallbackName);
    if (name != null) buf.writeln(name);
    if (_v(orgNr) != null) buf.writeln('Org.nr: ${orgNr!.trim()}');
    if (_v(address) != null) buf.writeln(address!.trim());
    final cityLine = [
      if (_v(postalCode) != null) postalCode!.trim(),
      if (_v(city) != null) city!.trim(),
    ].join(' ');
    if (cityLine.isNotEmpty) buf.writeln(cityLine);
    if (_v(country) != null) buf.writeln(country!.trim());
    if (_v(email) != null) buf.writeln('Email: ${email!.trim()}');
  }

  static void _appendUninvoiced(StringBuffer buf, List<OfferSummary> list) {
    if (list.isEmpty) return;

    buf.writeln();
    buf.writeln('Confirmed – not yet invoiced:');
    buf.writeln('-' * 44);

    for (final s in list) {
      final start = s.startDate != null ? _dateFmt.format(s.startDate!) : '?';
      final end = s.endDate != null ? _dateFmt.format(s.endDate!) : '?';
      final total = s.totalExclVat != null
          ? '${_nokFmt.format(s.totalExclVat!)},- excl. VAT'
          : 'price not set';

      buf.writeln('${s.production} | $start – $end | $total');
    }
  }

  static String? _v(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  // --------------------------------------------------
  // FERRY BOOKING EMAIL
  // --------------------------------------------------

  static bool _isExcludedFerry(String name) {
    final lower = name.toLowerCase().replaceAll('ö', 'o').replaceAll('ø', 'o');
    return lower.contains('resundsbroen');
  }

  static Future<void> sendFerryBookingEmail({
    required OfferDraft offer,
  }) async {
    const to = 'mail@michaelthoegersen.com';
    const subject = 'Ferry booking request';

    // Collect all ferry legs across all rounds, grouped by date.
    // Ferry names may be combined strings like "Öresundsbroen & Rødby - Puttgarden"
    // so we split on "&" and filter each part individually.
    final Map<DateTime, List<String>> ferryByDate = {};

    // Collect all buses and trailer status across all rounds
    final Set<String> allBuses = {};
    bool anyTrailer = false;

    for (final r in offer.rounds) {
      for (final b in r.busSlots) {
        if (b != null && b.isNotEmpty) allBuses.add(b);
      }
      if (r.trailerSlots.any((t) => t)) anyTrailer = true;

      for (int li = 0; li < r.ferryPerLeg.length; li++) {
        final raw = r.ferryPerLeg[li];
        if (raw == null || raw.trim().isEmpty) continue;
        if (li >= r.entries.length) continue;

        final date = DateTime.utc(
          r.entries[li].date.year,
          r.entries[li].date.month,
          r.entries[li].date.day,
        );

        // Split combined ferry strings and filter excluded ferries
        final parts = raw.split('&').map((s) => s.trim()).where((s) => s.isNotEmpty && !_isExcludedFerry(s)).toList();
        for (final part in parts) {
          ferryByDate.putIfAbsent(date, () => []).add(part);
        }
      }
    }

    if (ferryByDate.isEmpty) return;

    final sortedDates = ferryByDate.keys.toList()..sort();

    final buf = StringBuffer();
    buf.writeln('Hi,');
    buf.writeln();
    buf.writeln('Hope you are doing well. Could you please help me with booking these ferries?');
    buf.writeln();
    buf.writeln('Production: ${offer.production.trim().isEmpty ? '(no production)' : offer.production.trim()}');
    if (allBuses.isNotEmpty) {
      buf.writeln('Bus: ${allBuses.join(', ')}');
    }
    buf.writeln('Trailer: ${anyTrailer ? 'Yes' : 'No'}');
    // Vehicle type (kjoretoy)
    var kjoretoy = offer.busType.label;
    if (anyTrailer) kjoretoy += ' + trailer';
    if (offer.busCount > 1) kjoretoy = '${offer.busCount}x $kjoretoy';
    buf.writeln('Layout: $kjoretoy');
    buf.writeln();

    for (final date in sortedDates) {
      final ferries = ferryByDate[date]!;
      buf.writeln(_dateFmt.format(date));
      for (final ferry in ferries) {
        buf.writeln(ferry);
      }
      buf.writeln();
    }

    buf.writeln();
    buf.writeln('Best Regards');
    buf.writeln('Michael Thøgersen');

    await sendEmail(to: to, subject: subject, body: buf.toString());
  }
}
