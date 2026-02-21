import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';

class OfferStorageService {
  static SupabaseClient get sb => Supabase.instance.client;

  /// 🔔 Dashboard / Edit page kan lytte på denne
  static final ValueNotifier<int> recentOffersRefresh =
      ValueNotifier<int>(0);

  /// 🔔 Emits draft ID whenever any draft is saved — used for cross-tab refresh
  static final _savedController = StreamController<String>.broadcast();
  static Stream<String> get draftSaved => _savedController.stream;

  // ============================================================
  // SAVE (INSERT / UPDATE)
  // ============================================================
  static Future<String> saveDraft({
    String? id,
    required OfferDraft offer,
    double? totalExclVat,
  }) async {
    final payload = _offerToDbPayload(offer);

    // ✅ Hent innlogget bruker
    final user = sb.auth.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    final userId = user.id;

    // -----------------------------
    // UPDATE
    // -----------------------------
    if (id != null && id.isNotEmpty) {
      await sb.from('offers').update({
        ...payload,
        if (totalExclVat != null) 'total_excl_vat': totalExclVat,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': userId,
      }).eq('id', id);

      recentOffersRefresh.value++;
      _savedController.add(id);
      return id;
    }
    debugPrint(jsonEncode(payload));
    // -----------------------------
    // INSERT
    // -----------------------------
    final res = await sb.from('offers').insert({
      ...payload,
      if (totalExclVat != null) 'total_excl_vat': totalExclVat,

      // Audit
      'created_by': userId,
      'updated_by': userId,

      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).select('id').single();

    recentOffersRefresh.value++;
    _savedController.add(res['id'] as String);

    return res['id'] as String;
  }

  // ============================================================
  // DELETE
  // ============================================================
  static Future<void> deleteDraft(String id) async {
    await sb.from('offers').delete().eq('id', id);

    recentOffersRefresh.value++;
  }

  // ============================================================
  // LOAD SINGLE
  // ============================================================
  static Future<OfferDraft> loadDraft(String id) async {
    final res = await sb
        .from('offers')
        .select()
        .eq('id', id)
        .single();

    return _offerFromDb(res);
  }

  // ============================================================
  // LOAD RECENT (WITH PROFILES)
  // ============================================================
  static Future<List<Map<String, dynamic>>> loadRecentOffers({
  int limit = 20,
}) async {
  final user = sb.auth.currentUser;
  if (user == null) return [];

  // 1. Hent offers
  final offersRes = await sb
    .from('offers')
    .select(
      'id, production, company, created_at, updated_at, created_by, updated_by, payload, offer_json',
    )
    .order('updated_at', ascending: false)
    .limit(limit);

  final offers = (offersRes as List).cast<Map<String, dynamic>>();

  if (offers.isEmpty) return [];

  // 2. Samle alle userIds
  final Set<String> userIds = {};

  for (final o in offers) {
    if (o['created_by'] != null) {
      userIds.add(o['created_by']);
    }
    if (o['updated_by'] != null) {
      userIds.add(o['updated_by']);
    }
  }

  if (userIds.isEmpty) return offers;

  // 3. Hent profiles
  final profilesRes = await sb
      .from('profiles')
      .select('id, name')
      .filter('id', 'in', '(${userIds.join(',')})');

  final profiles = (profilesRes as List).cast<Map<String, dynamic>>();

  // 4. Lag lookup-map
  final Map<String, String> profileMap = {};

  for (final p in profiles) {
    profileMap[p['id']] = p['name'] ?? 'Unknown';
  }

  // 5. Koble navn på offers
  for (final o in offers) {
    o['created_name'] =
        profileMap[o['created_by']] ?? 'Unknown';

    o['updated_name'] =
        profileMap[o['updated_by']] ?? 'Unknown';
  }

  return offers;
}

  // ============================================================
  // PAYLOAD
  // ============================================================
  static Map<String, dynamic> _offerToDbPayload(OfferDraft offer) {
  final jsonMap = _offerToJson(offer);
  final jsonString = jsonEncode(jsonMap);

  return {
    'title': _buildTitle(offer),

    'company': offer.company.trim(),
    'contact': offer.contact.trim(),
    'production': offer.production.trim(),

    // ✅ RIKTIG STATUS
    'status': offer.status,

    'bus_count': offer.busCount,
    'bus_type': offer.busType.name,

    'payload': jsonMap,
    'offer_json': jsonString,
  };
}


  // ============================================================
  // TITLE
  // ============================================================
  static String _buildTitle(OfferDraft offer) {
    final prod =
        offer.production.trim().isEmpty ? "Offer" : offer.production.trim();

    DateTime? earliest;

    for (final r in offer.rounds) {
      for (final e in r.entries) {
        if (earliest == null || e.date.isBefore(earliest)) {
          earliest = e.date;
        }
      }
    }

    final stamp = earliest == null
        ? DateTime.now()
            .toIso8601String()
            .substring(0, 10)
            .replaceAll("-", "")
        : "${earliest.year}"
            "${earliest.month.toString().padLeft(2, '0')}"
            "${earliest.day.toString().padLeft(2, '0')}";

    return "$prod $stamp";
  }

  // ============================================================
  // TO JSON
  // ============================================================
  static Map<String, dynamic> _offerToJson(OfferDraft offer) {
  return {
    'company': offer.company,
    'contact': offer.contact,
    'phone': offer.phone,
    'email': offer.email,
    'production': offer.production,

    'busCount': offer.busCount,
    'busType': offer.busType.name,
    'bus': offer.bus,
    'globalBusSlots': offer.globalBusSlots,
    'pricingModel': offer.pricingModel,

    // ⭐⭐⭐ LEGG TIL DENNE LINJA
    'pricingOverride': offer.pricingOverride?.toJson(),

    'totalOverride': offer.totalOverride,

    'rounds': offer.rounds.map((r) {
      return {
        'startLocation': r.startLocation,
        'trailer': r.trailer,
        'pickupEveningFirstDay': r.pickupEveningFirstDay,
        'bus': r.bus,
        'busSlots': r.busSlots,
        'trailerSlots': r.trailerSlots,
        'ferryPerLeg': r.ferryPerLeg,
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
  // ============================================================
  // FROM DB
  // ============================================================
  static OfferDraft _offerFromDb(Map<String, dynamic> row) {
  dynamic raw = row['payload'];
  raw ??= row['offer_json'];

  final Map<String, dynamic> data =
      raw is String ? jsonDecode(raw) : (raw as Map<String, dynamic>);

  final draft = OfferDraft(
  company: (data['company'] ?? '') as String,
  contact: (data['contact'] ?? '') as String,

  // ✅ LEGG TIL
  phone: (data['phone'] ?? '') as String,
  email: (data['email'] ?? '') as String,

  production: (data['production'] ?? '') as String,

  status: (row['status'] ?? 'Draft') as String,

  busCount: (data['busCount'] ?? 1) as int,

  busType: _busTypeFromName(
    (data['busType'] ?? 'sleeper12') as String,
  ),

  bus: data['bus'] as String?,
   pricingOverride: data['pricingOverride'] != null
      ? OfferPricingOverride.fromJson(
          Map<String, dynamic>.from(data['pricingOverride']),
        )
      : null,
);

  final rounds = (data['rounds'] as List?) ?? [];

  for (int i = 0; i < draft.rounds.length; i++) {
    if (i >= rounds.length) break;

    final r = rounds[i] as Map<String, dynamic>;

    draft.rounds[i].startLocation =
        (r['startLocation'] ?? '') as String;

    draft.rounds[i].trailer =
        (r['trailer'] ?? false) as bool;

    draft.rounds[i].pickupEveningFirstDay =
        (r['pickupEveningFirstDay'] ?? false) as bool;

    draft.rounds[i].bus = r['bus'] as String?;
    if (r['busSlots'] != null) {
  draft.rounds[i].busSlots =
      List<String?>.from(r['busSlots']);
} else {
  draft.rounds[i].busSlots[0] = draft.rounds[i].bus;
}

if (r['trailerSlots'] != null) {
  draft.rounds[i].trailerSlots =
      List<bool>.from(r['trailerSlots']);
} else {
  draft.rounds[i].trailerSlots[0] =
      draft.rounds[i].trailer;
}

if (r['ferryPerLeg'] != null) {
  draft.rounds[i].ferryPerLeg =
      List<String?>.from(r['ferryPerLeg']);
}

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

    draft.rounds[i].entries
        .sort((a, b) => a.date.compareTo(b.date));
  }

  if (data['globalBusSlots'] != null) {
    draft.globalBusSlots = List<String?>.from(data['globalBusSlots']);
  }

  draft.pricingModel = (data['pricingModel'] as String?) ?? 'norsk';

  // ✅ BACKUP: hvis bare ligger i JSON
  if (draft.bus == null && data['bus'] != null) {
    draft.bus = data['bus'] as String?;
  }

  draft.totalOverride = (data['totalOverride'] as num?)?.toDouble();

  return draft;
}

  static BusType _busTypeFromName(String name) {
    for (final t in BusType.values) {
      if (t.name == name) return t;
    }
    return BusType.sleeper12;
  }
  // ============================================================
// SAVE TO SAMLETDATA (Calendar)
// ============================================================
static Future<void> saveToSamletData({
  required OfferDraft offer,
  required String kilde,
  required Map<DateTime, double> kmByDate,
  required Map<DateTime, double> timeByDate,
}) async {
  final sb = Supabase.instance.client;

  final produksjon = offer.production.trim();
  final kjoretoy = _buildKjoretoy(offer);

  for (final date in kmByDate.keys) {
    final dato = DateTime(date.year, date.month, date.day);

    await sb.from('samletdata').upsert({
      'dato': dato.toIso8601String().substring(0, 10),
      'sted': '',
      'venue': '',
      'adresse': '',
      'km': kmByDate[date]?.toString() ?? '',
      'tid': timeByDate[date]?.toString() ?? '',
      'produksjon': produksjon,
      'kjoretoy': kjoretoy,
      'pris': '',
      'getin': '',
      'kommentarer': '',
      'ferry': '',
      'vedlegg': '',
      'contact': offer.contact,
      'status': offer.status,
      'kilde': kilde,
    },
    onConflict: 'dato,kilde');
  }
}
static String _buildKjoretoy(OfferDraft offer) {
  var type = offer.busType.label;

  if (offer.rounds.any((r) => r.trailer)) {
    type += " + trailer";
  }

  if (offer.busCount > 1) {
    type = "${offer.busCount}x $type";
  }

  return type;
}
}