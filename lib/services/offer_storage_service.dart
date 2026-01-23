import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';

class OfferStorageService {
  static SupabaseClient get sb => Supabase.instance.client;

  /// ✅ Notifier som Dashboard kan lytte på (refresh recent offers)
  static final ValueNotifier<int> recentOffersRefresh = ValueNotifier<int>(0);

  // ------------------------------------------------------------
  // ✅ SAVE (insert/update)
  // ------------------------------------------------------------
  static Future<String> saveDraft({
    required OfferDraft offer,
    String? id,
  }) async {
    final payload = _offerToDbPayload(offer);

    // INSERT
    if (id == null || id.trim().isEmpty) {
      final res = await sb.from('offers').insert(payload).select('id').single();

      final newId = res['id'] as String;

      // ✅ refresh dashboard
      recentOffersRefresh.value++;

      return newId;
    }

    // UPDATE
    await sb.from('offers').update(payload).eq('id', id);

    // ✅ refresh dashboard
    recentOffersRefresh.value++;

    return id;
  }

  // ------------------------------------------------------------
  // ✅ LOAD (draft by id)
  // ------------------------------------------------------------
  static Future<OfferDraft> loadDraft(String id) async {
    final res =
        await sb.from('offers').select().eq('id', id).limit(1).single();

    return _offerFromDb(res);
  }

  // ------------------------------------------------------------
  // ✅ LIST recent offers (Dashboard / Edit page)
  // ------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> loadRecentOffers(
      {int limit = 20}) async {
    final res = await sb
        .from('offers')
        .select('id, title, production, status, company, contact, created_at, updated_at')
        .order('updated_at', ascending: false)
        .limit(limit);

    return (res as List).cast<Map<String, dynamic>>();
  }

  // ------------------------------------------------------------
  // 🔁 Convert -> DB payload
  //
  // ✅ IMPORTANT:
  // Supabase tabellen din krever:
  // - title NOT NULL
  // - payload NOT NULL   ✅✅✅
  // ------------------------------------------------------------
  static Map<String, dynamic> _offerToDbPayload(OfferDraft offer) {
    final jsonMap = _offerToJson(offer);
    final jsonString = jsonEncode(jsonMap);

    return {
      // ✅ disse må alltid være med
      'title': _buildTitle(offer),
      'company': offer.company.trim(),
      'contact': offer.contact.trim(),
      'production': offer.production.trim(),
      'status': 'Draft',

      'bus_count': offer.busCount,
      'bus_type': offer.busType.name,

      // ✅ DB krever payload NOT NULL
      // JSONB kan sendes som Map (best) eller String.
      // Vi sender Map for JSONB.
      'payload': jsonMap,

      // ✅ hvis du fortsatt vil beholde offer_json også:
      // (kan fjernes senere når alt fungerer)
      'offer_json': jsonString,
    };
  }

  // ------------------------------------------------------------
  // ✅ Generate safe title
  // ------------------------------------------------------------
  static String _buildTitle(OfferDraft offer) {
    final prod =
        offer.production.trim().isEmpty ? "Offer" : offer.production.trim();

    // Finn tidligste dato i hele offeret
    DateTime? earliest;
    for (final r in offer.rounds) {
      for (final e in r.entries) {
        if (earliest == null || e.date.isBefore(earliest)) earliest = e.date;
      }
    }

    final stamp = earliest == null
        ? DateTime.now()
            .toIso8601String()
            .substring(0, 10)
            .replaceAll("-", "")
        : "${earliest.year}${earliest.month.toString().padLeft(2, '0')}${earliest.day.toString().padLeft(2, '0')}";

    return "$prod $stamp";
  }

  // ------------------------------------------------------------
  // 🔁 Convert OfferDraft -> JSON
  // ------------------------------------------------------------
  static Map<String, dynamic> _offerToJson(OfferDraft offer) {
    return {
      'company': offer.company,
      'contact': offer.contact,
      'production': offer.production,
      'busCount': offer.busCount,
      'busType': offer.busType.name,
      'rounds': offer.rounds.map((r) {
        return {
          'startLocation': r.startLocation,
          'trailer': r.trailer,
          'pickupEveningFirstDay': r.pickupEveningFirstDay,
          'entries': r.entries.map((e) {
            return {
              'date': e.date.toIso8601String(),
              'location': e.location,
              'extra': e.extra,
            };
          }).toList(),
        };
      }).toList(),
    };
  }

  // ------------------------------------------------------------
  // 🔁 Convert DB -> OfferDraft
  //
  // ✅ Les først fra payload (riktig kolonne)
  // fallback til offer_json hvis payload ikke finnes
  // ------------------------------------------------------------
  static OfferDraft _offerFromDb(Map<String, dynamic> row) {
    dynamic raw = row['payload'];

    // fallback
    raw ??= row['offer_json'];

    // payload kan komme som Map eller String
    final Map<String, dynamic> data =
        raw is String ? jsonDecode(raw) : (raw as Map<String, dynamic>);

    final draft = OfferDraft(
      company: (data['company'] ?? '') as String,
      contact: (data['contact'] ?? '') as String,
      production: (data['production'] ?? '') as String,
      busCount: (data['busCount'] ?? 1) as int,
      busType: _busTypeFromName((data['busType'] ?? 'sleeper12') as String),
    );

    final rounds = (data['rounds'] as List?) ?? [];

    for (int i = 0; i < draft.rounds.length; i++) {
      if (i >= rounds.length) break;

      final r = rounds[i] as Map<String, dynamic>;
      draft.rounds[i].startLocation = (r['startLocation'] ?? '') as String;
      draft.rounds[i].trailer = (r['trailer'] ?? false) as bool;
      draft.rounds[i].pickupEveningFirstDay =
          (r['pickupEveningFirstDay'] ?? false) as bool;

      draft.rounds[i].entries.clear();

      final entries = (r['entries'] as List?) ?? [];
      for (final e in entries) {
        final em = e as Map<String, dynamic>;
        draft.rounds[i].entries.add(
          RoundEntry(
            date: DateTime.parse(em['date'] as String),
            location: (em['location'] ?? '') as String,
            extra: (em['extra'] ?? '') as String,
          ),
        );
      }

      draft.rounds[i].entries.sort((a, b) => a.date.compareTo(b.date));
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