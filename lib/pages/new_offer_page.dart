

import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/calendar_sync_service.dart';
import '../supabase_clients.dart';
import '../models/app_settings.dart';
import '../models/offer_draft.dart';
import 'package:tourflow/services/trip_calculator.dart';
import '../services/offer_pdf_service.dart';
import '../state/settings_store.dart';
import '../widgets/offer_preview.dart';
import '../services/offer_storage_service.dart';
import 'package:go_router/go_router.dart';
import '../widgets/new_company_dialog.dart';
import '../services/pdf_tour_parser.dart';
import '../widgets/route_popup_dialog.dart';
import 'package:flutter/foundation.dart';
import '../services/bus_availability_service.dart';

// ✅ NY: bruker routes db for autocomplete + route lookup
import '../services/routes_service.dart';
import '../services/customers_service.dart';
import '../state/current_offer_store.dart';
import '../models/round_calc_result.dart';
import 'package:flutter/foundation.dart';
import '../platform/pdf_saver.dart';
// ignore: avoid_web_libraries_in_flutter

class NewOfferPage extends StatefulWidget {
  /// ✅ Hvis du sender inn offerId -> åpner den eksisterende draft
  final String? offerId;

  const NewOfferPage({super.key, this.offerId});

  @override
  State<NewOfferPage> createState() => _NewOfferPageState();
}

class _NewOfferPageState extends State<NewOfferPage> {

  String _safeFolderName(String name) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'[\/\\\:\*\?\"\<\>\|]'), "_");
  s = s.replaceAll(RegExp(r"\s+"), " ");
  return s;
}

  Future<String?> _pickBusSimple() async {

  const buses = [
    "CSS_1034",
    "CSS_1023",
    "CSS_1008",
    "YCR 682",
    "ESW 337",
    "WYN 802",
    "RLC 29G",
    "Rental 1 (Hasse)",
    "Rental 2 (Rickard)",
  ];

  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Select bus"),
      content: SizedBox(
        width: 300,
        child: ListView(
          shrinkWrap: true,
          children: buses.map((bus) {
            return ListTile(
              leading: const Icon(Icons.directions_bus),
              title: Text(bus),
              onTap: () => Navigator.pop(context, bus),
            );
          }).toList(),
        ),
      ),
    ),
  );
}


  // ===================================================
  // STATE FIELDS
  // ===================================================

  int roundIndex = 0;

  bool _busLoaded = false;

  final FocusNode _locationFocus = FocusNode();

  final Map<int, RoundCalcResult> _roundCalcCache = {};

  List<bool> _travelBefore = [];
// ✅ MANGLER DISSE
  List<String> _locationSuggestions = [];
  bool _loadingSuggestions = false;

// ---------------------------------------------------
// KM / ROUTE STATE (MANGLER – MÅ VÆRE MED)
// ---------------------------------------------------

bool _loadingKm = false;
String? _kmError;

// Per entry (current round)
Map<int, double?> _kmByIndex = {};
Map<int, double> _ferryByIndex = {};
Map<int, double> _tollByIndex = {};
Map<int, String> _extraByIndex = {};
Map<int, Map<String, double>> _countryKmByIndex = {};

// Global caches (per route)
final Map<String, double?> _distanceCache = {};
final Map<String, double> _ferryCache = {};
final Map<String, double> _tollCache = {};
final Map<String, String> _extraCache = {};
final Map<String, String> _ferryNameCache = {};
Map<int, String> _ferryNameByIndex = {};
final Map<String, Map<String, double>> _countryKmCache = {};
  // ===================================================
  // ROUND BREAKDOWN
  // ===================================================

  String _buildRoundBreakdown(
    int roundIndex,
    RoundCalcResult r,
    AppSettings s,
  ) {
    final b = StringBuffer();

    b.writeln("ROUND CALCULATION");
    b.writeln("----------------------------");

    // ================= DAYS =================

    b.writeln(
      "${r.billableDays} days × ${_nok(s.dayPrice)}"
      " = ${_nok(r.dayCost)}",
    );

    // ================= KM =================

    b.writeln("");
    b.writeln("KM:");

    b.writeln("  Included: ${r.includedKm.toStringAsFixed(0)} km");
    b.writeln(
      "  Driven:   ${(r.includedKm + r.extraKm).toStringAsFixed(0)} km",
    );

    if (r.extraKm > 0) {
      b.writeln(
        "  Extra:    ${r.extraKm.toStringAsFixed(0)} × "
        "${_nok(s.extraKmPrice)}"
        " = ${_nok(r.extraKmCost)}",
      );
    } else {
      b.writeln("  Extra:    0");
    }

    // ================= D.DRIVE =================

    if (r.dDriveDays > 0) {
      b.writeln("");
      b.writeln(
        "D.Drive: ${r.dDriveDays} × ${_nok(s.dDriveDayPrice)}"
        " = ${_nok(r.dDriveCost)}",
      );
    }

    // ================= TRAILER =================

    final trailerTotal = r.trailerDayCost + r.trailerKmCost;

    if (trailerTotal > 0) {
      b.writeln("");
      b.writeln("Trailer: ${_nok(trailerTotal)}");
    }

    // ================= FERRY =================

    if (r.ferryCost > 0) {
      b.writeln("");
      b.writeln("Ferry: ${_nok(r.ferryCost)}");
    }

    // ================= FLIGHTS =================
if (r.flightCost > 0) {
  b.writeln("");
  b.writeln("Flights: ${_nok(r.flightCost)}");
}

    // ================= TOLL =================

    if (r.tollCost > 0) {
      b.writeln("");
      b.writeln("Toll:");

      final round = offer.rounds[roundIndex];

      final int maxLegs = [
        round.entries.length,
        r.tollPerLeg.length,
      ].reduce((a, b) => a < b ? a : b);

      for (int i = 0; i < maxLegs; i++) {
        final toll = r.tollPerLeg[i];

        if (toll <= 0) continue;

        final date = _fmtDate(round.entries[i].date);

        final from = i == 0
            ? _norm(round.startLocation)
            : _norm(round.entries[i - 1].location);

        final to = _norm(round.entries[i].location);

        b.writeln(
          "  $date  $from → $to: ${_nok(toll)}",
        );
      }

      b.writeln("  ----------------");
      b.writeln("  Total: ${_nok(r.tollCost)}");
    }

    // ================= TOTAL =================

    b.writeln("");
    b.writeln("----------------------------");
    b.writeln("TOTAL: ${_nok(r.totalCost)}");

    return b.toString();
  }
// ---------------------------------------------------
// Recalculate all rounds (for PDF + totals)
// ---------------------------------------------------
Future<void> _recalcAllRounds() async {
  final Map<int, RoundCalcResult> newCache = {};

  for (int i = 0; i < offer.rounds.length; i++) {
    final res = await _calcRound(i);
    newCache[i] = res;
  }

  if (!mounted) return;

  setState(() {
    _roundCalcCache
      ..clear()
      ..addAll(newCache);
  });
}

  // ===================================================
  // BUS PICKER
  // ===================================================

 Future<String?> _pickBus() async {
  final currentRound = offer.rounds[roundIndex];

  if (currentRound.entries.isEmpty) {
    debugPrint("📦 No dates yet → simple picker");
    return _pickBusSimple();
  }

  final startDate = currentRound.entries.first.date;
  final endDate = currentRound.entries.last.date;

  final start = startDate.toIso8601String().substring(0, 10);
  final end = endDate.toIso8601String().substring(0, 10);

  debugPrint("📅 Checking availability from $start → $end");

  // =====================================================
  // 🔥 HENT BUSSER SOM ER OPPTATT – MEN IKKE DENNE DRAFTEN
  // =====================================================

  var query = Supabase.instance.client
      .from('samletdata')
      .select('kilde,draft_id')
      .gte('dato', start)
      .lte('dato', end);

  final busy = await query;

  final busySet = (busy as List)
      .where((e) {
        final draft = e['draft_id']?.toString();

        // ⭐ IGNORER DENNE DRAFTEN
        if (_draftId != null && draft == _draftId) {
          return false;
        }

        return true;
      })
      .map((e) => e['kilde']?.toString())
      .whereType<String>()
      .toSet();

  debugPrint("❌ Busy buses: $busySet");

  // =====================================================
  // 🔥 HENT ALLE BUSSER
  // =====================================================

  // =====================================================
// 🔥 ENTERPRISE BUS SOURCE (same as Calendar)
// =====================================================

const allBuses = [
  "CSS_1034",
  "CSS_1023",
  "CSS_1008",
  "YCR 682",
  "ESW 337",
  "WYN 802",
  "RLC 29G",
  "Rental 1 (Hasse)",
  "Rental 2 (Rickard)",
];

  final available =
      allBuses.where((b) => !busySet.contains(b)).toList();

  debugPrint("✅ Available buses: $available");

  if (!mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Select available bus"),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: available.map((bus) {
            return ListTile(
              leading: const Icon(Icons.directions_bus),
              title: Text(bus),
              onTap: () => Navigator.pop(dialogContext, bus),
            );
          }).toList(),
        ),
      ),
    ),
  );
}


  // ===================================================
  // DEFAULT OFFER
  // ===================================================

  final OfferDraft offer = OfferDraft(
    company: '',
    contact: '',
    production: '',
  );


  final TextEditingController companyCtrl = TextEditingController();
  final TextEditingController contactCtrl = TextEditingController();
  final TextEditingController productionCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();

  final TextEditingController startLocCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();


  DateTime? selectedDate;


  // ===================================================
  // DRAFT
  // ===================================================

  String? _draftId;

  bool _loadingDraft = false;

  String? _selectedBus;


  // ===================================================
  // SERVICES
  // ===================================================

  final RoutesService _routesService = RoutesService();

  SupabaseClient get sb => Supabase.instance.client;


  // ===================================================
  // LIFECYCLE
  // ===================================================

  @override
  void initState() {
    super.initState();

    companyCtrl.text = offer.company;
    contactCtrl.text = offer.contact;
    productionCtrl.text = offer.production;
    phoneCtrl.text = offer.phone ?? '';
    emailCtrl.text = offer.email ?? '';

    _syncRoundControllers();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = widget.offerId?.trim();

      if (id != null && id.isNotEmpty) {
        await _loadDraft(id);
      } else {
        await _recalcKm();
      }
    });
  }


  @override
  void dispose() {
    companyCtrl.dispose();
    contactCtrl.dispose();
    productionCtrl.dispose();
    startLocCtrl.dispose();
    locationCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();

    _locationFocus.dispose();

    super.dispose();
  }
  

  // ===================================================
  // HELPERS
  // ===================================================

  void _clearAllRouteCache() {
  _distanceCache.clear();
  _ferryCache.clear();
  _tollCache.clear();
  _extraCache.clear();
  _countryKmCache.clear();

  debugPrint("🔥 Route cache cleared");
}

  DateTime _getNextAvailableDate() {
  final entries = offer.rounds[roundIndex].entries;

  if (entries.isEmpty) {
    return DateTime.now();
  }

  final latest = entries
      .map((e) => e.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  return latest.add(const Duration(days: 1));
}

  void _syncRoundControllers() {
    startLocCtrl.text =
        offer.rounds[roundIndex].startLocation;

    selectedDate = _getNextAvailableDate();

    locationCtrl.text = '';
  }
  


  // ===================================================
  // DRAFT LOADING
  // ===================================================

  Future<void> _loadDraft(String id) async {
  _loadingDraft = true;

  try {
    final fresh =
        await OfferStorageService.loadDraft(id);

    if (fresh == null || !mounted) return;

    setState(() {

      // ✅ KOPIER DATA – IKKE ERSTATT OBJEKT
      offer.company    = fresh.company;
      offer.contact    = fresh.contact;
      offer.phone      = fresh.phone;
      offer.email      = fresh.email;
      offer.production = fresh.production;
      offer.status     = fresh.status;

      // ⭐ ENTERPRISE: global bus brukes ikke lenger
      // offer.bus = fresh.bus;   <-- kan beholdes om legacy trengs

      offer.busCount   = fresh.busCount;
      offer.busType    = fresh.busType;

      // =========================
      // ROUNDS (FULL SYNC)
      // =========================
      for (int i = 0; i < offer.rounds.length; i++) {

        if (i >= fresh.rounds.length) break;

        final src = fresh.rounds[i];
        final dst = offer.rounds[i];

        dst.startLocation = src.startLocation;
        dst.trailer = src.trailer;
        dst.pickupEveningFirstDay =
            src.pickupEveningFirstDay;

        // ⭐⭐⭐ DETTE VAR DET SOM MANGLER ⭐⭐⭐
        dst.bus = src.bus;

        dst.entries
          ..clear()
          ..addAll(src.entries);
      }

      // =========================
      // TEXTFIELDS
      // =========================
      companyCtrl.text = offer.company;
      contactCtrl.text = offer.contact;
      productionCtrl.text = offer.production;
      phoneCtrl.text = offer.phone ?? '';
      emailCtrl.text = offer.email ?? '';

      _draftId = id;
      roundIndex = 0;

      _syncRoundControllers();
    });

    // ⭐ VIKTIG — oppdater preview model
    CurrentOfferStore.set(offer);

    await _recalcKm();

  } finally {
    _loadingDraft = false;
  }
}
// ------------------------------------------------------------
// ✅ Load bus from samletdata for this draft
// ------------------------------------------------------------
// ------------------------------------------------------------
// ✅ Load bus from samletdata for this draft
// ------------------------------------------------------------
Future<void> _loadBusForDraft(String draftId) async {
  try {
    final res = await sb
        .from('samletdata')
        .select('kilde')
        .eq('draft_id', draftId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (!mounted) return;

    final bus = res?['kilde']?.toString().trim();

    setState(() {
      if (bus != null && bus.isNotEmpty) {
        _selectedBus = bus;
      }

      _busLoaded = true;
    });

    debugPrint("Loaded bus: $_selectedBus");

  } catch (e) {
    debugPrint("Load bus failed: $e");

    if (mounted) {
      setState(() => _busLoaded = true);
    }
  }
}

// ------------------------------------------------------------
// ✅ DB autocomplete for location
// ------------------------------------------------------------
Future<void> _loadPlaceSuggestions(String query) async {
    final q = query.trim();

    // justerer terskel om du vil, men 2 tegn fungerer fint
    if (q.length < 2) {
      if (!mounted) return;
      setState(() => _locationSuggestions = []);
      return;
    }

    setState(() => _loadingSuggestions = true);

    try {
      final res = await _routesService.searchPlaces(q, limit: 12);
      if (!mounted) return;
      setState(() => _locationSuggestions = res);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationSuggestions = []);
    } finally {
      if (!mounted) return;
      setState(() => _loadingSuggestions = false);
    }
  }
  

  // ------------------------------------------------------------
  // Small helpers
  // ------------------------------------------------------------
// ------------------------------------------------------------
// MANUAL BUS CHANGE
// ------------------------------------------------------------
Future<void> _changeBusManually() async {
  final picked = await _pickBus();
  if (picked == null || picked.isEmpty) return;

  setState(() {
    // ⭐ ENTERPRISE: sett på AKTIV ROUND
    offer.rounds[roundIndex].bus = picked;
  });

  CurrentOfferStore.set(offer); // ⭐ viktig for preview sync
}
  Future<void> _openMissingRouteDialog({
  String? from,
  String? to,
}) async {

  final fromCtrl = TextEditingController(text: from ?? '');
  final toCtrl = TextEditingController(text: to ?? '');
  final kmCtrl = TextEditingController();
  final tollCtrl = TextEditingController();
  final extraCtrl = TextEditingController(); // ✅ NY // ✅ NY

  await showDialog(
    context: context,
    builder: (ctx) {

      return AlertDialog(
        title: const Text("Add missing route"),

        content: SizedBox(
  width: 420,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [

      TextField(
        controller: fromCtrl,
        decoration: const InputDecoration(
          labelText: "From",
        ),
      ),

      const SizedBox(height: 10),

      TextField(
        controller: toCtrl,
        decoration: const InputDecoration(
          labelText: "To",
        ),
      ),

      const SizedBox(height: 10),

      TextField(
        controller: kmCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: "KM",
        ),
      ),

      const SizedBox(height: 10),

      // ✅ NY: TOLL
      TextField(
        controller: tollCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: "Toll (Nightliner)",
        ),
      ),
      // ✅ NY: EXTRA
TextField(
  controller: extraCtrl,
  decoration: const InputDecoration(
    labelText: "Extra (ex: Ferry)",
  ),
),
    ],
  ),
),

        actions: [

          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),

          FilledButton(
            onPressed: () async {

              final from = _norm(fromCtrl.text);
              final to = _norm(toCtrl.text);
              final km =
                  double.tryParse(kmCtrl.text.replaceAll(',', '.'));
              final toll =
                  double.tryParse(tollCtrl.text.replaceAll(',', '.')) ?? 0.0;
              final extra = extraCtrl.text.trim();    

              if (from.isEmpty || to.isEmpty || km == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Fill all fields"),
                  ),
                );
                return;
              }

              try {

                // ---------------- SAVE TO DB ----------------
                await sb.from('routes_all').insert({
  'from_place': from,
  'to_place': to,
  'distance_total_km': km,
  'toll_nightliner': toll,              
  'extra': extra,
});

// 🔥 CLEAR CACHE
final key = _cacheKey(from, to);

_distanceCache.remove(key);
_ferryCache.remove(key);
_tollCache.remove(key);
_extraCache.remove(key);
_countryKmCache.remove(key);

if (!mounted) return;

Navigator.pop(ctx);

                // ---------------- RECALC ----------------
                await _recalcKm();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Route saved ✅"),
                  ),
                );

              } catch (e) {

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Save failed: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },

            child: const Text("Save"),
          ),
        ],
      );
    },
  );
}
// ------------------------------------------------------------
// HELPERS
// ------------------------------------------------------------
// ------------------------------------------------------------
// Check if leg has Travel/Off before
// ------------------------------------------------------------
bool _hasTravelBefore(List<RoundEntry> entries, int index) {
  if (index <= 0) return false;

  int i = index - 1;

  while (i >= 0) {
    final loc = _norm(entries[i].location).toLowerCase();

    if (loc == 'travel' || loc == 'off') {
      return true;
    }

    if (loc.isNotEmpty) {
      return false;
    }

    i--;
  }

  return false;
}
// ------------------------------------------------------------
// FIND PREVIOUS REAL LOCATION (skip Travel / Off)
// ------------------------------------------------------------
String _findPreviousRealLocation(
  List<RoundEntry> entries,
  int index,
  String startLocation,
) {
  for (int i = index - 1; i >= 0; i--) {
    final loc = _norm(entries[i].location).toLowerCase();

    if (loc != 'travel' && loc != 'off' && loc.isNotEmpty) {
      return _norm(entries[i].location);
    }
  }

  // Fallback → bruk start
  return _norm(startLocation);
}
bool _isNoDriveLeg(String from, String to) {
  final f = _norm(from).toLowerCase();
  final t = _norm(to).toLowerCase();

  if (f == t) return true;

  if (t == 'travel') return true;
  if (t == 'off') return true;

  return false;
}
String _norm(String s) {
  return s.trim().replaceAll(RegExp(r"\s+"), " ");
}

String _cacheKey(String from, String to) {
  return "${_norm(from).toLowerCase()}__${_norm(to).toLowerCase()}";
}

String _fmtDate(DateTime d) {
  return "${d.day.toString().padLeft(2, '0')}"
      ".${d.month.toString().padLeft(2, '0')}"
      ".${d.year}";
}

Future<void> _pickDate() async {
  final now = DateTime.now();

  final picked = await showDatePicker(
    context: context,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
    initialDate: selectedDate ?? now,
  );

  if (picked != null && mounted) {
    setState(() {
      selectedDate = picked;
    });
  }
}
String _validStatus(String? status) {
  const allowed = [
  "Draft",
  "Inquiry",
  "Confirmed",
  "Cancelled",
];

  if (status == null) return "Draft";
  if (allowed.contains(status)) return status;

  return "Draft";
}
  // ============================================================
// VAT ENGINE (Foreign VAT calculation)
// ============================================================

static const Map<String, double> _vatRates = {
  'DK': 0.25,
  'DE': 0.19,
  'AT': 0.10,
  'PL': 0.08,
  'BE': 0.06,
  'SI': 0.095,
  'HR': 0.25,
  'Other': 0.0,
};

String _mapCalendarStatus(String? status) {
  switch (status?.toLowerCase()) {
    case 'draft':
      return 'Draft';

    case 'inquiry':
      return 'Inquiry';

    case 'confirmed':
      return 'Confirmed';

    case 'cancelled':
      return 'Cancelled';

    default:
      return 'Draft';
  }
}

// --------------------------------------------
// Collect km from all rounds
// --------------------------------------------
Map<String, double> _collectAllCountryKm() {
  final Map<String, double> result = {};

  for (final map in _countryKmByIndex.values) {
    map.forEach((country, km) {
      if (km <= 0) return;

      result[country] = (result[country] ?? 0) + km;
    });
  }

  return result;
}

// --------------------------------------------
// Calculate foreign VAT
// --------------------------------------------
Map<String, double> _calculateForeignVat({
  required double basePrice,
  required Map<String, double> countryKm,
}) {
  final totalKm =
      countryKm.values.fold<double>(0, (a, b) => a + b);

  if (totalKm == 0) return {};

  final Map<String, double> result = {};

  countryKm.forEach((country, km) {
    final rate = _vatRates[country] ?? 0;

    if (rate <= 0 || km <= 0) return;

    final share = km / totalKm;
    final vat = basePrice * share * rate;

    if (vat > 0) {
      result[country] = vat;
    }
  });

  return result;
}

// --------------------------------------------
// VAT UI box
// --------------------------------------------
Widget _buildVatBox(
  Map<String, double> vatMap,
  double excl,
  double incl,
) {
  if (vatMap.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "Total excl VAT: ${_nok(excl)}",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          "Total incl VAT: ${_nok(incl)}",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Text(
        "Foreign VAT",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),

      const SizedBox(height: 6),

      ...vatMap.entries.map((e) {
        final rate = (_vatRates[e.key] ?? 0) * 100;

        return Text(
          "${e.key} (${rate.toStringAsFixed(1)}%): ${_nok(e.value)}",
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
      }),

      const SizedBox(height: 6),

      Text(
        "Total VAT: ${_nok(vatMap.values.fold(0, (a, b) => a + b))}",
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),

      const Divider(),

      Text(
        "Total excl VAT: ${_nok(excl)}",
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),

      const SizedBox(height: 4),

      Text(
        "Total incl VAT: ${_nok(incl)}",
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ],
  );
}

// ------------------------------------------------------------
// Open route preview for first missing leg
// ------------------------------------------------------------
Future<void> _openRoutePreview() async {
  final round = offer.rounds[roundIndex];

  if (round.entries.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No routes yet.")),
    );
    return;
  }

  String? from;
  String? to;

  // ================================
  // FINN FØRSTE REELLE LEG (IKKE OFF / TRAVEL)
  // ================================
  for (int i = 0; i < round.entries.length; i++) {
    final f = i == 0
        ? _norm(round.startLocation)
        : _norm(round.entries[i - 1].location);

    final t = _norm(round.entries[i].location);
    final tLower = t.toLowerCase();

    if (f.isEmpty) continue;
    if (f == t) continue;
    if (tLower == 'off' || tLower == 'travel') continue;

    from = f;
    to = t;
    break;
  }

  if (from == null || to == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("No valid route leg found."),
      ),
    );
    return;
  }

  // ================================
  // COLLECT STOPS (VIA)
  // ================================
  final stops = <String>[];

  for (final e in round.entries) {
    final loc = _norm(e.location);
    final l = loc.toLowerCase();

    if (loc.isEmpty) continue;
    if (l == 'off' || l == 'travel') continue;

    stops.add(loc);
  }

  // ================================
  // ÅPNE POPUP UANSETT KM
  // ================================
  final updated = await showDialog<bool>(
    context: context,
    builder: (_) => RoutePopupDialog(
      start: from!,
      stops: stops,
    ),
  );

  if (updated == true) {
    _clearAllRouteCache();
    await _recalcKm();
  }
}
  Future<void> _onAddMissingRoutePressed() async {

  final round = offer.rounds[roundIndex];

  if (round.entries.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No routes yet.")),
    );
    return;
  }

  debugPrint("---- ADD MISSING ROUTE ----");

  String? suggestedFrom;
  String? suggestedTo;

  final count = round.entries.length;

  // ================================
  // FIND FIRST REAL MISSING LEG
  // ================================
  for (int i = 0; i < count; i++) {

    final km = _kmByIndex[i];

    final from = i == 0
        ? _norm(round.startLocation)
        : _norm(round.entries[i - 1].location);

    final to = _norm(round.entries[i].location);

    debugPrint("[$i] $from → $to | km=$km");

    // ❗ hopp over hvis samme sted
    if (from == to) continue;

    // ❗ mangler km = denne vil vi ha
    if (km == null) {
      suggestedFrom = from;
      suggestedTo = to;
      break;
    }
  }

  // ================================
  // FALLBACK (hvis noe er rart)
  // ================================
  if (suggestedFrom == null || suggestedTo == null) {
    suggestedFrom = _norm(round.startLocation);
    suggestedTo = _norm(round.entries.first.location);
  }

  debugPrint("SUGGESTED: $suggestedFrom → $suggestedTo");

  // ================================
  // OPEN DIALOG
  // ================================
  await _openMissingRouteDialog(
    from: suggestedFrom,
    to: suggestedTo,
  );
}
  // ------------------------------------------------------------
  // ✅ Save draft to Supabase (insert/update)
  // ------------------------------------------------------------
  // ------------------------------------------------------------
// ✅ Save draft to Supabase (insert/update)
// ------------------------------------------------------------
// ------------------------------------------------------------
// ✅ Save draft to Supabase (insert/update) - FIXED
// ------------------------------------------------------------
Future<void> _saveDraft() async {
  // Auto-set Draft hvis tom
  offer.status = _validStatus(offer.status);

  // ----------------------------------------
  // ⛔ Vent hvis draft lastes
  // ----------------------------------------
  if (_loadingDraft) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Loading draft… please wait"),
      ),
    );
    return;
  }

  try {

    // ----------------------------------------
    // ✅ SYNC ALL ROUNDS BEFORE SAVE
    // ----------------------------------------
    for (int i = 0; i < offer.rounds.length; i++) {
      final r = offer.rounds[i];

      // Aktiv runde → fra input
      if (i == roundIndex) {
        r.startLocation = _norm(startLocCtrl.text);
      }

      // Normalize (safety)
      r.startLocation = _norm(r.startLocation);
    }

    // ----------------------------------------
    // ✅ Lagre i MODELL (ÉN GANG)
    // ----------------------------------------
    final current = CurrentOfferStore.current.value;

    if (current != null) {

      offer.company    = current.company;
      offer.contact    = current.contact;
      offer.phone      = current.phone;
      offer.email      = current.email;
      offer.production = current.production;

      offer.busCount   = current.busCount;
      offer.busType    = current.busType;

      // ✅ VIKTIG: SYNC ROUNDS (inkl trailer)
      for (int i = 0; i < offer.rounds.length; i++) {
        if (i >= current.rounds.length) break;

        offer.rounds[i].trailer =
            current.rounds[i].trailer;

        offer.rounds[i].pickupEveningFirstDay =
            current.rounds[i].pickupEveningFirstDay;
      }
    }

    // ----------------------------------------
    // Save to DB
    // ----------------------------------------
    final id = await OfferStorageService.saveDraft(
      id: _draftId,
      offer: offer,
    );

    if (id == null || id.isEmpty) {
      throw Exception("Failed to save draft (no ID)");
    }

    _draftId = id;

    // ----------------------------------------
    // Reload from DB (SOURCE OF TRUTH)
    // ----------------------------------------
    final freshOffer =
        await OfferStorageService.loadDraft(id);

    if (freshOffer == null) {
      throw Exception("Failed to reload draft");
    }

    // 🔥 FULL SYNC BACK TO MAIN MODEL
    offer.company    = freshOffer.company;
    offer.contact    = freshOffer.contact;
    offer.phone      = freshOffer.phone;
    offer.email      = freshOffer.email;
    offer.production = freshOffer.production;
    offer.status     = freshOffer.status;
    offer.busCount   = freshOffer.busCount;
    offer.busType    = freshOffer.busType;

    // 🔥 GLOBAL BUS ER FJERNET (enterprise multi-bus)
    // offer.bus = freshOffer.bus;

    phoneCtrl.text = offer.phone ?? '';
    emailCtrl.text = offer.email ?? '';

    freshOffer.status =
        _mapCalendarStatus(freshOffer.status);

    CurrentOfferStore.set(freshOffer);

    // ----------------------------------------
    // Sync back to state
    // ----------------------------------------
    offer.status = freshOffer.status;

    // ----------------------------------------
    // Sync calendar (PER ROUND BUS)
    // ----------------------------------------
    await CalendarSyncService.syncFromOffer(
  freshOffer,
  draftId: id,
  calcCache: _roundCalcCache,
);

    // ----------------------------------------
    // UI refresh
    // ----------------------------------------
    if (mounted) {
      setState(() {});
    }

    // ----------------------------------------
    // Feedback (vis første buss som finnes)
    // ----------------------------------------
    String? firstBus;

    for (final r in offer.rounds) {
      if (r.bus != null && r.bus!.isNotEmpty) {
        firstBus = r.bus;
        break;
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          firstBus != null
              ? "Lagret på $firstBus ✅"
              : "Lagret ✅",
        ),
      ),
    );

  } catch (e, st) {

    debugPrint("SAVE ERROR:");
    debugPrint(e.toString());
    debugPrint(st.toString());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Save failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}



// ------------------------------------------------------------
// ✅ Scan PDF and import tour
// ------------------------------------------------------------
// ------------------------------------------------------------
// ✅ Scan PDF and import tour
// ------------------------------------------------------------
// ------------------------------------------------------------
Future<void> _exportPdf() async {

  // 🔥 HENT SISTE SYNC FRA STORE
  final current = CurrentOfferStore.current.value;

  if (current != null) {
    offer.company    = current.company;
    offer.contact    = current.contact;
    offer.phone      = current.phone;
    offer.email      = current.email;
    offer.production = current.production;
    offer.bus        = current.bus;
  } else {
    // fallback (burde nesten aldri skje)
    offer.phone = phoneCtrl.text.trim();
    offer.email = emailCtrl.text.trim();
  }
  try {

    // ===============================
    // Kalkuler alle runder først
    // ===============================
    final Map<int, RoundCalcResult> roundCalc = {};

    for (int i = 0; i < offer.rounds.length; i++) {
      final res = await _calcRound(i);
      roundCalc[i] = res;
    }
debugPrint("=== EXPORT DEBUG ===");
debugPrint("Name: ${offer.contact}");
debugPrint("Phone: ${offer.phone}");
debugPrint("Email: ${offer.email}");
    // ===============================
    // Generer PDF
    // ===============================
    debugPrint("===== PDF TRAILER DEBUG =====");

for (int i = 0; i < offer.rounds.length; i++) {
  debugPrint("EXPORT round $i trailer = ${offer.rounds[i].trailer}");
}
    final bytes = await OfferPdfService.generatePdf(
      offer,
      roundCalc,
    );

    // ===============================
    // Lagre fil
    // ===============================
    final path = await _savePdfToFile(bytes);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("PDF saved: $path")),
    );

  } catch (e, st) {

    debugPrint("EXPORT ERROR:");
    debugPrint(e.toString());
    debugPrint(st.toString());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Export failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
// ------------------------------------------------------------
// ✅ Scan PDF with preview
// ------------------------------------------------------------
Future<void> _scanPdf() async {
  try {
    debugPrint("===== PDF SCAN START =====");

    final text =
        await PdfTourParser.pickAndExtractText();

    if (text == null || text.trim().isEmpty) {
      debugPrint("❌ No text from PDF");
      return;
    }

    debugPrint("===== RAW TEXT =====");
    debugPrint(text.substring(0, text.length > 1000 ? 1000 : text.length));

    final parsedRounds = PdfTourParser.parse(text);

    debugPrint("===== PARSED ROUNDS =====");
    debugPrint("Rounds found: ${parsedRounds.length}");

    if (parsedRounds.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No tour data found in PDF"),
        ),
      );

      debugPrint("❌ Parser returned EMPTY");
      return;
    }

    setState(() {

      debugPrint("===== RESET UI ROUNDS =====");

      // 🔹 RESET ALT FØRST
      for (int i = 0; i < offer.rounds.length; i++) {
        offer.rounds[i].startLocation = '';
        offer.rounds[i].entries.clear();
        offer.rounds[i].trailer = false;
        offer.rounds[i].pickupEveningFirstDay = false;
      }

      debugPrint("===== APPLY PARSED DATA =====");

      // 🔹 FYLL FRA PARSER
      for (int i = 0;
          i < parsedRounds.length && i < offer.rounds.length;
          i++) {

        final uiRound = offer.rounds[i];
        final parsed = parsedRounds[i];

        debugPrint("Round ${i + 1}: start=${parsed.startLocation}");

        uiRound.startLocation =
            _norm(parsed.startLocation);

        for (final e in parsed.entries) {

          debugPrint(
            "  ${e.date} -> ${e.location}",
          );

          uiRound.entries.add(
            RoundEntry(
              date: e.date,
              location: _norm(e.location),
              extra: '',
            ),
          );
        }
      }

      roundIndex = 0;
      _syncRoundControllers();
    });

    await _recalcKm();

    debugPrint("===== PDF IMPORT DONE =====");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("PDF imported correctly ✅"),
      ),
    );

  } catch (e, st) {

    debugPrint("===== PDF IMPORT ERROR =====");
    debugPrint(e.toString());
    debugPrint(st.toString());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("PDF import failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
  // ------------------------------------------------------------
  // ✅ KM + ferry + toll + extra lookup from Supabase
  // ------------------------------------------------------------
  Future<double?> _fetchLegData({
  required String from,
  required String to,
  required int index,
}) async {
  final fromN = _norm(from);
  final toN   = _norm(to);
  final key   = _cacheKey(fromN, toN);

  debugPrint("LOOKUP: '$fromN' → '$toN'");

  // ===================================================
  // CACHE HIT
  // ===================================================
  if (_distanceCache.containsKey(key)) {
    _ferryByIndex[index]     = _ferryCache[key] ?? 0.0;
    _tollByIndex[index]      = _tollCache[key] ?? 0.0;
    _extraByIndex[index]     = _extraCache[key] ?? '';
    _ferryNameByIndex[index]= _ferryNameCache[key] ?? '';
    _countryKmByIndex[index]= _countryKmCache[key] ?? {};

    return _distanceCache[key];
  }

  try {
    final res = await _routesService.findRoute(
      from: fromN,
      to: toN,
    );

    // ===================================================
    // NO ROUTE FOUND
    // ===================================================
    if (res == null) {
      _distanceCache[key]  = null;
      _ferryCache[key]     = 0.0;
      _tollCache[key]      = 0.0;
      _extraCache[key]     = '';
      _ferryNameCache[key]= '';
      _countryKmCache[key]= {};

      _ferryByIndex[index]     = 0.0;
      _tollByIndex[index]      = 0.0;
      _extraByIndex[index]     = '';
      _ferryNameByIndex[index]= '';
      _countryKmByIndex[index]= {};

      return null;
    }

    // ===================================================
    // READ DB FIELDS (SINGLE SOURCE OF TRUTH)
    // ===================================================
    final kmRaw      = (res['distance_total_km'] as num?)?.toDouble();
    final km         = (kmRaw == null || kmRaw <= 0) ? null : kmRaw;

    final ferryPrice =
        (res['ferry_price'] as num?)?.toDouble() ?? 0.0;

    final ferryName =
        (res['ferry_name'] as String?)?.trim() ?? '';

    final toll =
        (res['toll_nightliner'] as num?)?.toDouble() ?? 0.0;

    final extra =
        (res['extra'] as String?)?.trim() ?? '';

    // ===================================================
    // COUNTRY KM BREAKDOWN
    // ===================================================
    final Map<String, double> countryKm = {
      if ((res['km_dk'] as num?) != null && (res['km_dk'] as num) > 0)
        'DK': (res['km_dk'] as num).toDouble(),
      if ((res['km_de'] as num?) != null && (res['km_de'] as num) > 0)
        'DE': (res['km_de'] as num).toDouble(),
      if ((res['km_be'] as num?) != null && (res['km_be'] as num) > 0)
        'BE': (res['km_be'] as num).toDouble(),
      if ((res['km_pl'] as num?) != null && (res['km_pl'] as num) > 0)
        'PL': (res['km_pl'] as num).toDouble(),
      if ((res['km_at'] as num?) != null && (res['km_at'] as num) > 0)
        'AT': (res['km_at'] as num).toDouble(),
      if ((res['km_hr'] as num?) != null && (res['km_hr'] as num) > 0)
        'HR': (res['km_hr'] as num).toDouble(),
      if ((res['km_si'] as num?) != null && (res['km_si'] as num) > 0)
        'SI': (res['km_si'] as num).toDouble(),
      if ((res['km_other'] as num?) != null && (res['km_other'] as num) > 0)
        'Other': (res['km_other'] as num).toDouble(),
    };

    // ===================================================
    // CACHE WRITE
    // ===================================================
    _distanceCache[key]   = km;
    _ferryCache[key]      = ferryPrice;
    _tollCache[key]       = toll;
    _extraCache[key]      = extra;
    _ferryNameCache[key] = ferryName;
    _countryKmCache[key] = countryKm;

    // ===================================================
    // PER-INDEX WRITE (UI + CALC)
    // ===================================================
    _ferryByIndex[index]      = ferryPrice;
    _tollByIndex[index]       = toll;
    _extraByIndex[index]      = extra;
    _ferryNameByIndex[index] = ferryName;
    _countryKmByIndex[index] = countryKm;

    debugPrint(
      "[ROUTE] $fromN → $toN | km=$km ferry='$ferryName' price=$ferryPrice",
    );

    return km;
  } catch (e, st) {
    debugPrint("❌ ROUTE LOOKUP FAILED: $e");
    debugPrint(st.toString());

    _distanceCache[key]   = null;
    _ferryCache[key]      = 0.0;
    _tollCache[key]       = 0.0;
    _extraCache[key]      = '';
    _ferryNameCache[key] = '';
    _countryKmCache[key] = {};

    _ferryByIndex[index]      = 0.0;
    _tollByIndex[index]       = 0.0;
    _extraByIndex[index]      = '';
    _ferryNameByIndex[index] = '';
    _countryKmByIndex[index] = {};

    return null;
  }
}

// ------------------------------------------------------------
// Recalculate legs for CURRENT round (with Travel/Off merge)
// ------------------------------------------------------------
// ------------------------------------------------------------
// Recalculate legs for CURRENT round (with Travel merge only)
// ------------------------------------------------------------
Future<void> _recalcKm() async {
  final round = offer.rounds[roundIndex];
  final start = _norm(round.startLocation);

  // ---------------- EMPTY START ----------------
  if (start.isEmpty) {
    if (!mounted) return;

    setState(() {
      _kmByIndex = {};
      _ferryByIndex = {};
      _tollByIndex = {};
      _extraByIndex = {};
      _ferryNameByIndex = {};
      _countryKmByIndex = {};
      _travelBefore = [];
      _kmError = null;
    });

    return;
  }

  final entries = round.entries;

  setState(() {
    _loadingKm = true;
    _kmError = null;
  });

  // ---------------- TEMP STORAGE ----------------
  final Map<int, double?> kmByIndex = {};
  final Map<int, double> ferryByIndex = {};
  final Map<int, double> tollByIndex = {};
  final Map<int, String> extraByIndex = {};
  final Map<int, String> ferryNameByIndex = {};
  final Map<int, Map<String, double>> countryKmByIndex = {};

  final List<bool> travelBefore =
      List<bool>.filled(entries.length, false);

  bool missing = false;

  int? pendingTravelIndex;
  bool inTravelBlock = false;

  // ===================================================
  // MAIN LOOP
  // ===================================================
  for (int i = 0; i < entries.length; i++) {
    final from = _findPreviousRealLocation(entries, i, start);
    final toRaw = _norm(entries[i].location);
    final toLower = toRaw.toLowerCase();

    final bool isTravel = toLower == 'travel';
    final bool isOff    = toLower == 'off';

    // ---------------- OFF ----------------
    if (isOff) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';
      ferryNameByIndex[i] = '';
      countryKmByIndex[i] = {};

      pendingTravelIndex = null;
      inTravelBlock = false;
      travelBefore[i] = false;
      continue;
    }

    // ---------------- TRAVEL ----------------
    if (isTravel) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';
      ferryNameByIndex[i] = '';
      countryKmByIndex[i] = {};

      if (pendingTravelIndex == null) {
        pendingTravelIndex = i; // første Travel i blokken
      }

      inTravelBlock = true;
      continue;
    }

    // ---------------- SAME PLACE ----------------
    if (_norm(from).toLowerCase() == toLower) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';
      ferryNameByIndex[i] = '';
      countryKmByIndex[i] = {};

      pendingTravelIndex = null;
      inTravelBlock = false;
      continue;
    }

    // ---------------- LOOKUP ----------------
    final km = await _fetchLegData(
      from: from,
      to: toRaw,
      index: i,
    );

    if (km == null) {
      missing = true;
    }

    final key = _cacheKey(from, toRaw);

    final ferry = _ferryCache[key] ?? 0.0;
    final toll  = _tollCache[key] ?? 0.0;
    final extra = _extraCache[key] ?? '';
    final ferryName = _ferryNameCache[key] ?? '';
    final country = Map<String, double>.from(
      _countryKmCache[key] ?? {},
    );

    // ===================================================
    // MERGE TRAVEL BLOCK
    // ===================================================
    if (pendingTravelIndex != null && km != null && km > 0) {
      kmByIndex[pendingTravelIndex] = km;
      ferryByIndex[pendingTravelIndex] = ferry;
      tollByIndex[pendingTravelIndex] = toll;
      extraByIndex[pendingTravelIndex] = extra;
      ferryNameByIndex[pendingTravelIndex] = ferryName;
      countryKmByIndex[pendingTravelIndex] = country;

      // null ut dagens leg
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';
      ferryNameByIndex[i] = '';
      countryKmByIndex[i] = {};

      travelBefore[pendingTravelIndex] = true;
      travelBefore[i] = true;

      pendingTravelIndex = null;
      inTravelBlock = false;
      continue;
    }

    // ===================================================
    // NORMAL LEG
    // ===================================================
    kmByIndex[i] = km ?? 0;
    ferryByIndex[i] = ferry;
    tollByIndex[i] = toll;
    extraByIndex[i] = extra;
    ferryNameByIndex[i] = ferryName;
    countryKmByIndex[i] = country;

    travelBefore[i] = inTravelBlock;
    inTravelBlock = false;
  }

  // ===================================================
  // APPLY TO MODEL
  // ===================================================
  for (int i = 0; i < entries.length; i++) {
    entries[i] = entries[i].copyWith(
      extra: extraByIndex[i] ?? '',
      countryKm: countryKmByIndex[i] ?? {},
    );
  }

  if (!mounted) return;

  // ===================================================
  // APPLY TO STATE
  // ===================================================
  setState(() {
    _kmByIndex = kmByIndex;
    _ferryByIndex = ferryByIndex;
    _tollByIndex = tollByIndex;
    _extraByIndex = extraByIndex;
    _ferryNameByIndex = ferryNameByIndex;
    _countryKmByIndex = countryKmByIndex;
    _travelBefore = travelBefore;

    _loadingKm = false;
    _kmError = missing
        ? "Missing routes in routes_all. Check place names / direction."
        : null;
  });

  await _recalcAllRounds();
}
Future<void> _validateSelectedBus() async {
  final round = offer.rounds[roundIndex];

  if (offer.bus == null) return;
  if (round.entries.isEmpty) return;

  final availability =
      await BusAvailabilityService.fetchAvailability(
    start: round.entries.first.date,
    end: round.entries.last.date,
  );

  if (availability[offer.bus] == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Selected bus is no longer available"),
      ),
    );
  }
}
  // ------------------------------------------------------------
  // Add entry
  // ------------------------------------------------------------
  Future<void> _addEntry() async {
  final loc = _norm(locationCtrl.text);

  // ---------------- VALIDATION ----------------

  if (selectedDate == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pick a date first.")),
    );
    return;
  }

  if (loc.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Enter a location.")),
    );
    return;
  }

  if (_norm(startLocCtrl.text).isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Start location must be set first.")),
    );
    return;
  }

  // ---------------- PREP ----------------

  final nextIndex =
      offer.rounds[roundIndex].entries.length;

  final extra =
      _extraByIndex[nextIndex] ?? '';

  // ---------------- ADD ----------------

  setState(() {
    offer.rounds[roundIndex].entries.add(
      RoundEntry(
        date: selectedDate!,
        location: loc,
        extra: extra,
      ),
    );

    // Sort by date
    offer.rounds[roundIndex].entries
        .sort((a, b) => a.date.compareTo(b.date));

    // Auto next day
    selectedDate =
        selectedDate!.add(const Duration(days: 1));

    // Clear input
    locationCtrl.clear();
    _locationSuggestions = [];
  });

  // ---------------- REFOCUS ----------------

  FocusScope.of(context)
      .requestFocus(_locationFocus);

  // ---------------- RECALC ----------------

  await _recalcKm();
  await _recalcAllRounds();
}

  Future<void> _pasteManyLines(List<String> lines) async {

  // ---------------- VALIDATION ----------------

  if (selectedDate == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Pick a date first, then paste."),
      ),
    );
    return;
  }

  final clean = lines
      .map(_norm)
      .where((e) => e.isNotEmpty)
      .toList();

  if (clean.isEmpty) return;

  // ---------------- ADD ----------------

  setState(() {
    for (final loc in clean) {

      final idx =
          offer.rounds[roundIndex].entries.length;

      final extra =
          _extraByIndex[idx] ?? '';

      offer.rounds[roundIndex].entries.add(
        RoundEntry(
          date: selectedDate!,
          location: loc,
          extra: extra,
        ),
      );

      // Next day
      selectedDate =
          selectedDate!.add(const Duration(days: 1));
    }

    // Sort
    offer.rounds[roundIndex].entries
        .sort((a, b) => a.date.compareTo(b.date));

    // Clear input
    locationCtrl.clear();
    _locationSuggestions = [];
  });

  // ---------------- REFOCUS ----------------

  FocusScope.of(context)
      .requestFocus(_locationFocus);

  // ---------------- RECALC ----------------

  await _recalcKm();
}
// ------------------------------------------------------------
// Edit entry
// ------------------------------------------------------------
Future<void> _editEntry(int index) async {

  final entry =
      offer.rounds[roundIndex].entries[index];

  DateTime tempDate = entry.date;

  final tempLocCtrl =
      TextEditingController(text: entry.location);

  // ---------------- DIALOG ----------------

  final updated = await showDialog<RoundEntry>(
    context: context,
    builder: (dialogCtx) {

      return StatefulBuilder(
        builder: (_, setDialogState) {

          return AlertDialog(
            title: const Text("Edit entry"),

            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // -------- DATE --------
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_fmtDate(tempDate)),
                    onPressed: () async {

                      final picked =
                          await showDatePicker(
                        context: dialogCtx,
                        firstDate:
                            DateTime(tempDate.year - 1),
                        lastDate:
                            DateTime(tempDate.year + 5),
                        initialDate: tempDate,
                      );

                      if (picked != null) {
                        setDialogState(() {
                          tempDate = picked;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  // -------- LOCATION --------
                  TextField(
                    controller: tempLocCtrl,
                    decoration: const InputDecoration(
                      labelText: "Location",
                      prefixIcon: Icon(Icons.place),
                    ),
                  ),
                ],
              ),
            ),

            actions: [

              TextButton(
                onPressed: () =>
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(),
                child: const Text("Cancel"),
              ),

              FilledButton(
                onPressed: () {

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop(
                    RoundEntry(
                      date: tempDate,
                      location:
                          _norm(tempLocCtrl.text),
                      extra: entry.extra,
                    ),
                  );
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      );
    },
  );

  if (updated == null) return;

  // ---------------- APPLY ----------------

  setState(() {
    offer.rounds[roundIndex].entries[index] =
        updated;

    offer.rounds[roundIndex].entries
        .sort((a, b) => a.date.compareTo(b.date));
  });

  // ---------------- REFOCUS ----------------

  FocusScope.of(context)
      .requestFocus(_locationFocus);

  // ---------------- RECALC ----------------

  await _recalcKm();
}
// ------------------------------------------------------------
// ✅ Per-round calc helper (Travel merge + Off = ignore)
// ------------------------------------------------------------
// ------------------------------------------------------------

Future<RoundCalcResult> _calcRound(int ri) async {

  final round = offer.rounds[ri];

  final entries = [...round.entries]
    ..sort((a, b) => a.date.compareTo(b.date));

  // ---------------- DATES ----------------
  final dates = entries
      .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
      .toList();

  if (dates.isEmpty) {

    final empty = TripCalculator.calculateRound(
      settings: SettingsStore.current,
      dates: const [],
      pickupEveningFirstDay: false,
      trailer: round.trailer,
      totalKm: 0,
      legKm: const [],
      ferries: SettingsStore.current.ferries,
      tollPerLeg: const [],
      extraPerLeg: const [],
      hasTravelBefore: const [],
    );

    _roundCalcCache[ri] = empty;
    return empty;
  }

  final start = _norm(round.startLocation);

  final Map<int, double> kmByIndex = {};
  final Map<int, double> ferryByIndex = {};
  final Map<int, double> tollByIndex = {};
  final Map<int, String> extraByIndex = {};

  final List<bool> travelBefore =
      List<bool>.filled(entries.length, false);

  int? pendingTravelIndex;
  bool seenTravel = false;

  // ================= LOOP =================
  for (int i = 0; i < entries.length; i++) {

    final from = _findPreviousRealLocation(
      entries,
      i,
      start,
    );

    final toRaw = _norm(entries[i].location);
    final to = toRaw;

    final bool isTravel = to == 'travel';
    final bool isOff = to == 'off';

    // ---------- OFF ----------
    if (isOff) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      pendingTravelIndex = null;
      seenTravel = false;
      travelBefore[i] = false;
      continue;
    }

    // ---------- TRAVEL ----------
    if (isTravel) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';

      if (pendingTravelIndex == null) {
        pendingTravelIndex = i;
      }

      seenTravel = true;
      continue;
    }

    // ---------- SAME PLACE ----------
    if (_norm(from).toLowerCase() == to.toLowerCase()) {
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      pendingTravelIndex = null;
      seenTravel = false;
      continue;
    }

    // ---------- LOOKUP ----------
    final km = await _fetchLegData(
      from: from,
      to: toRaw,
      index: i,
    );

    final key = _cacheKey(from, toRaw);

    final ferry = _ferryCache[key] ?? 0.0;
    final toll  = _tollCache[key] ?? 0.0;
    final extra = _extraCache[key] ?? '';

    debugPrint("ROUND $ri LEG $i");
    debugPrint("  $from → $toRaw");
    debugPrint("  Ferry=$ferry Toll=$toll");

    // ---------- MERGE TRAVEL ----------
    if (pendingTravelIndex != null && km != null && km > 0) {

      kmByIndex[pendingTravelIndex] = km;

      ferryByIndex[pendingTravelIndex] =
          (ferryByIndex[pendingTravelIndex] ?? 0) + ferry;

      tollByIndex[pendingTravelIndex] =
          (tollByIndex[pendingTravelIndex] ?? 0) + toll;

      _ferryNameByIndex[pendingTravelIndex] =
          _ferryNameCache[key] ?? ''; // 🔧 ENDRET (kun her brukes ferry_name)

      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;

      travelBefore[pendingTravelIndex] = true;
      travelBefore[i] = true;

      pendingTravelIndex = null;
      seenTravel = false;
      continue;
    }

    // ---------- NORMAL ----------
    kmByIndex[i] = km ?? 0;
    ferryByIndex[i] = ferry;
    tollByIndex[i] = toll;
    extraByIndex[i] = extra;

    // 🔧 ENDRET: ferry_name lagres også på normale legs
    _ferryNameByIndex[i] = _ferryNameCache[key] ?? '';

    if (seenTravel) {
      travelBefore[i] = true;
      seenTravel = false;
    } else {
      travelBefore[i] = false;
    }
  }

  // ================= SUM =================
  final totalKm =
      kmByIndex.values.fold<double>(0, (a, b) => a + b);

  debugPrint("🖥️ UI RECALC");
  debugPrint("   → Ferry: ${ferryByIndex.values.fold(0.0, (a, b) => a + b)}");
  debugPrint("   → Toll : ${tollByIndex.values.fold(0.0, (a, b) => a + b)}");

  final int len = entries.length;

  final safeLegKm = List<double>.generate(
  len,
  (i) => kmByIndex[i] ?? 0.0,
);

final safeToll = List<double>.generate(
  len,
  (i) => tollByIndex[i] ?? 0.0,
);

final safeExtra = List<String>.generate(
  len,
  (i) => extraByIndex[i] ?? '',
);

final safeTravel = List<bool>.generate(
  len,
  (i) => i < travelBefore.length ? travelBefore[i] : false,
);

final safeFerryPerLeg = List<String?>.generate(
  len,
  (i) {
    final name = _ferryNameByIndex[i];
    return (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : null;
  },
);

  // ================= RESULT =================
  final result = TripCalculator.calculateRound(
    
    settings: SettingsStore.current,
    dates: dates,
    pickupEveningFirstDay: round.pickupEveningFirstDay,
    trailer: round.trailer,
    totalKm: totalKm,
    legKm: safeLegKm,
    ferries: SettingsStore.current.ferries,
    ferryPerLeg: safeFerryPerLeg, // 🔥 nå korrekt
    tollPerLeg: safeToll,
    extraPerLeg: safeExtra,
    hasTravelBefore: safeTravel,
  );
  // ⭐ MULTI BUS SUMMARY
final busCount =
    offer.rounds[ri].busSlots.whereType<String>().length == 0
        ? 1
        : offer.rounds[ri].busSlots.whereType<String>().length;

final scaled = RoundCalcResult(
  // ---------- NON PRICE ----------
  billableDays: result.billableDays,
  includedKm: result.includedKm,
  extraKm: result.extraKm,
  dDriveDays: result.dDriveDays,
  flightTickets: result.flightTickets,

  legKm: result.legKm,
  tollPerLeg: result.tollPerLeg,
  extraPerLeg: result.extraPerLeg,
  hasTravelBefore: result.hasTravelBefore, // ⭐ DENNE VAR SISTE

  // ---------- COSTS (scaled by buses) ----------
  dayCost: result.dayCost * busCount,
  extraKmCost: result.extraKmCost * busCount,
  dDriveCost: result.dDriveCost * busCount,

  trailerDayCost: result.trailerDayCost * busCount,
  trailerKmCost: result.trailerKmCost * busCount,

  ferryCost: result.ferryCost * busCount,
  tollCost: result.tollCost * busCount,
  flightCost: result.flightCost * busCount,

  totalCost: result.totalCost * busCount,
);
_roundCalcCache[ri] = scaled;
return scaled;

  debugPrint("📊 CALC ROUND");
  debugPrint("   → Ferry: ${result.ferryCost}");
  debugPrint("   → Toll : ${result.tollCost}");
  debugPrint("   → Total: ${result.totalCost}");

  _roundCalcCache[ri] = result;
  return result;
}

  // ------------------------------------------------------------
// ✅ Save PDF (FilePicker + WEB)
// ------------------------------------------------------------
Future<String> _savePdfToFile(Uint8List bytes) async {
  final production = offer.production.trim().isEmpty
      ? "UnknownProduction"
      : offer.production.trim();

  final safeProduction = _safeFolderName(production);

  final todayStamp =
      DateFormat("yyyyMMdd").format(DateTime.now());

  final defaultFileName =
      "Offer Nightliner $safeProduction $todayStamp.pdf";

  // 👇 ERSTATTER hele kIsWeb + FilePicker blokka
  return await savePdf(bytes, defaultFileName);
}

  String _nok(double v) => "${v.toStringAsFixed(0)},-";

    // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final round = offer.rounds[roundIndex];

// =====================================================
// CURRENT ROUND CALC (MIDTPANEL)
// =====================================================

final dates = round.entries
    .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
    .toList();

final totalKm =
    _kmByIndex.values.whereType<double>().fold<double>(0, (a, b) => a + b);

final travelFlags = _travelBefore;

// ✅ BRUK CACHE FØRST (riktig per runde)
final int len = round.entries.length;

final fallbackLegKm = List<double>.generate(
  len,
  (i) => _kmByIndex[i] ?? 0.0,
);

final fallbackToll = List<double>.generate(
  len,
  (i) => _tollByIndex[i] ?? 0.0,
);

final fallbackExtra = List<String>.generate(
  len,
  (i) => _extraByIndex[i] ?? '',
);

final fallbackTravel = List<bool>.generate(
  len,
  (i) => i < _travelBefore.length ? _travelBefore[i] : false,
);

final fallbackFerryPerLeg = List<String?>.generate(
  len,
  (i) {
    final name = _ferryNameByIndex[i];
    return (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : null;
  },
);

final calc = _roundCalcCache[roundIndex] ??
    TripCalculator.calculateRound(
      settings: SettingsStore.current,
      dates: dates,
      pickupEveningFirstDay: round.pickupEveningFirstDay,
      trailer: round.trailer,
      totalKm: fallbackLegKm.fold(0.0, (a, b) => a + b),
      legKm: fallbackLegKm,
      ferries: SettingsStore.current.ferries,
      ferryPerLeg: fallbackFerryPerLeg,
      tollPerLeg: fallbackToll,
      extraPerLeg: fallbackExtra,
      hasTravelBefore: fallbackTravel,
    );
// =====================================================
// ALL ROUNDS TOTAL (RIGHT CARD / VAT / TOTAL)
// =====================================================

double allRoundsTotal = 0;
double allRoundsFerry = 0;
double allRoundsToll = 0;

for (int i = 0; i < offer.rounds.length; i++) {
  final r = _roundCalcCache[i];

  if (r != null) {
    allRoundsTotal += r.totalCost;
    allRoundsFerry += r.ferryCost;
    allRoundsToll += r.tollCost;
  }
}

// =====================================================
// VAT CALC (BASED ON ALL ROUNDS)
// =====================================================

final basePrice =
    allRoundsTotal - allRoundsFerry - allRoundsToll;

final countryKm = _collectAllCountryKm();

final foreignVatMap = _calculateForeignVat(
  basePrice: basePrice,
  countryKm: countryKm,
);

final totalExVat = allRoundsTotal;

final totalIncVat =
    totalExVat +
    foreignVatMap.values.fold(0.0, (a, b) => a + b);


          // ============ LEFT ============

return Padding(
  padding: const EdgeInsets.all(18),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      // ================= LEFT =================
      SizedBox(
        width: 300,
        child: _LeftOfferCard(
          offer: offer,
          onExport: _exportPdf,
          onSave: _saveDraft,
          onScanPdf: _scanPdf,
          draftId: _draftId,
        ),
      ),

      const SizedBox(width: 14),

      // ================= CENTER =================
      Expanded(
        flex: 14,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ---------- HEADER ----------
              Row(
                children: [
                  Text(
                    "Rounds",
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int>(
                      value: roundIndex,
                      decoration: const InputDecoration(
                        labelText: "Round",
                        prefixIcon: Icon(Icons.repeat),
                      ),
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text("Round ${i + 1}"),
                        ),
                      ),
                      onChanged: (v) async {
                        if (v == null) return;

                        setState(() {
                          offer.rounds[roundIndex].startLocation =
                              _norm(startLocCtrl.text);

                          roundIndex = v;
                          _syncRoundControllers();
                        });

                        await _recalcKm();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ---------- START LOCATION ----------
              TextField(
                controller: startLocCtrl,
                onChanged: (_) async {
                  setState(() {
                    offer.rounds[roundIndex].startLocation =
                        _norm(startLocCtrl.text);
                  });

                  await _recalcKm();
                },
                decoration: const InputDecoration(
                  labelText: "Start location (for this round)",
                  prefixIcon: Icon(Icons.flag),
                ),
              ),

              const SizedBox(height: 10),

              // ---------- OPTIONS ----------
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [

    Row(
      children: [
        Checkbox(
          value: offer.rounds[roundIndex].pickupEveningFirstDay,
          onChanged: (v) async {
            setState(() {
              offer.rounds[roundIndex].pickupEveningFirstDay = v ?? false;
            });

            await _recalcKm();
          },
        ),
        const Text("Pickup evening (first day not billable)"),
      ],
    ),

    const SizedBox(height: 8),

    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(offer.busCount, (i) {

        final bus =
            offer.rounds[roundIndex].busSlots[i];

        final trailer =
            offer.rounds[roundIndex].trailerSlots[i];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [

                const Icon(Icons.directions_bus, size: 20),
                const SizedBox(width: 10),

                Text(
                  "Bus ${i + 1}:",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: InkWell(
                    onTap: () async {

  final picked = await _pickBus();
  if (picked == null) return;

  setState(() {

    offer.rounds[roundIndex]
        .busSlots[i] = picked;

    offer.rounds[roundIndex].bus =
        offer.rounds[roundIndex]
            .busSlots
            .firstWhere(
              (b) => b != null,
              orElse: () => null,
            );
  });

  CurrentOfferStore.set(offer);

  await _recalcAllRounds(); // ⭐ DENNE
},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        bus ?? "Select bus",
                        style: TextStyle(
                          color: bus == null ? Colors.grey : Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Row(
                  children: [
                    Checkbox(
                      value: trailer,
                      onChanged: (v) async {

                        setState(() {

                          offer.rounds[roundIndex]
                              .trailerSlots[i] = v ?? false;

                          offer.rounds[roundIndex].trailer =
                              offer.rounds[roundIndex]
                                  .trailerSlots
                                  .contains(true);
                        });

                        await _recalcAllRounds();
                      },
                    ),
                    const Text("Trailer"),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    ),
  ],
),

const SizedBox(height: 12),

              // ---------- ENTRY INPUT ----------
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                  color: cs.surface,
                ),
                child: Column(
                  children: [

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_month),
                            onPressed: _pickDate,
                            label: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                selectedDate == null
                                    ? "Pick date"
                                    : _fmtDate(selectedDate!),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    _LocationAutoComplete(
                      controller: locationCtrl,
                      focusNode: _locationFocus,
                      suggestions: _locationSuggestions,
                      onSubmit: _addEntry,
                      onPasteMulti: _pasteManyLines,
                      onQueryChanged: _loadPlaceSuggestions,
                    ),

                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_road),
                      label: const Text("Add missing route"),
                      onPressed: _openRoutePreview,
                    ),

                    if (_loadingSuggestions)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Searching routes…",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                    if (_kmError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _kmError!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
const SizedBox(height: 12),



// ---------- ROUTES ----------
Expanded(
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cs.outlineVariant),
      color: cs.surface,
    ),
    child: Column(
      children: [

        Row(
          children: const [
            Expanded(child: _RoutesTableHeader()),
          ],
        ),

        Divider(height: 14, color: cs.outlineVariant),

        if (round.entries.isEmpty)
          const Center(child: Text("No entries yet."))
        else
          Expanded(
            child: ListView.separated(
              itemCount: round.entries.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: cs.outlineVariant),
              itemBuilder: (_, i) {

                final e = round.entries[i];
                final km = _kmByIndex[i];

                final from = _findPreviousRealLocation(
                  round.entries,
                  i,
                  round.startLocation,
                );

                final to = _norm(e.location);
                final toLower = to.toLowerCase();

                final bool isSpecial =
                    toLower == 'off' || toLower == 'travel';

                final String routeText =
                    isSpecial ? to : "${_norm(from)} → $to";

                return _RoutesTableRow(
                  date: _fmtDate(e.date),
                  route: routeText,
                  km: km,
                  countryKm: _countryKmByIndex[i] ?? {},
                  onEdit: () => _editEntry(i),
                  onDelete: () async {
                    setState(() {
                      offer.rounds[roundIndex].entries.removeAt(i);
                    });
                    await _recalcKm();
                  },
                );
              },
            ),
          ),

        Divider(height: 14, color: cs.outlineVariant),

        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            Text("Billable days: ${calc.billableDays}",
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text("Included: ${calc.includedKm.toStringAsFixed(0)} km"),
            Text("Extra: ${calc.extraKm.toStringAsFixed(0)} km"),
            Text("Total: ${totalKm.toStringAsFixed(0)} km",
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),

        const SizedBox(height: 10),

      ],
    ),
  ),
),
            ], // 👈 CENTER children
          ),
        ),
      ),
      

          // ================= RIGHT =================
          SizedBox(
            width: 430,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

                    ValueListenableBuilder<OfferDraft?>(
  valueListenable: CurrentOfferStore.current,
  builder: (_, current, __) {
    return OfferPreview(
      offer: current ?? offer,
    );
  },
),

                    const SizedBox(height: 20),
                    // ================= STATUS =================
// ================= STATUS =================
Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.outlineVariant),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      const Text(
        "Status",
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),

      const SizedBox(height: 8),

      DropdownButtonFormField<String>(
        value: _validStatus(offer.status),
        isExpanded: true,

        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.flag),
          border: OutlineInputBorder(),
        ),

        items: const [
  DropdownMenuItem(
    value: "Draft",
    child: Text("📝 Draft"),
  ),
  DropdownMenuItem(
    value: "Inquiry",
    child: Text("📨 Inquiry"),
  ),
  DropdownMenuItem(
    value: "Confirmed",
    child: Text("✅ Confirmed"),
  ),
  DropdownMenuItem(
    value: "Cancelled",
    child: Text("❌ Cancelled"),
  ),
],

        onChanged: (v) {
          if (v == null) return;

          setState(() {
            offer.status = v;
          });
        },
      ),

      const SizedBox(height: 12),



Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.outlineVariant),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      Text(
        "Round calculation",
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),

      const SizedBox(height: 10),

      Text(
        _buildRoundBreakdown(
          roundIndex,
          calc,
          SettingsStore.current,
        ),
        style: const TextStyle(
          fontFamily: "monospace",
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
),

      // ---------- VAT ----------
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [

            const Text(
              "VAT summary",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 10),

            _buildVatBox(
              foreignVatMap,
              totalExVat,
              totalIncVat,
            ),
          ],
        ),
      ),
    ],
  ),
),
                    
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// =================================================
// LEFT CARD (WITH CONTACT ADMIN)
// =================================================

class _LeftOfferCard extends StatefulWidget {
  final OfferDraft offer;
  final Future<void> Function() onExport;
  final Future<void> Function() onSave;
  final Future<void> Function() onScanPdf;
  final String? draftId;

  const _LeftOfferCard({
  super.key,
  required this.offer,
  required this.onExport,
  required this.onSave,
  required this.onScanPdf, // ✅ NY
  required this.draftId,
});

  @override
  State<_LeftOfferCard> createState() => _LeftOfferCardState();
}

class _LeftOfferCardState extends State<_LeftOfferCard> {
  final SupabaseClient _client = Supabase.instance.client;

  final TextEditingController _companyCtrl = TextEditingController();

  bool _loading = false;

  List<Map<String, dynamic>> _companySuggestions = [];
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _productions = [];

  String? _contactId;
  String? _productionId;

  String? _currentCompanyId;

  // --------------------------------------------------
  // INIT
  // --------------------------------------------------
  @override
  void initState() {
    super.initState();

    if (widget.offer.company.isNotEmpty) {
      _companyCtrl.text = widget.offer.company;
      _restore(widget.offer.company);
    }
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    super.dispose();
  }
@override
void didUpdateWidget(covariant _LeftOfferCard oldWidget) {
  super.didUpdateWidget(oldWidget);

  final company = widget.offer.company;

  if (company.isNotEmpty) {
    _companyCtrl.text = company;
    _restore(company);
  }
}
  // --------------------------------------------------
  // RESTORE
  // --------------------------------------------------
  Future<void> _restore(String name) async {
    final r = await _client
        .from('companies')
        .select()
        .eq('name', name)
        .maybeSingle();

    if (r == null) return;

    _currentCompanyId = r['id'].toString();

    await _loadDetails(_currentCompanyId!);

    if (!mounted) return;

    setState(() {
      final c = _contacts.firstWhere(
        (e) => e['name'] == widget.offer.contact,
        orElse: () => {},
      );

      final p = _productions.firstWhere(
        (e) => e['name'] == widget.offer.production,
        orElse: () => {},
      );

      _contactId = c['id']?.toString();
      _productionId = p['id']?.toString();
    });
  }

  // --------------------------------------------------
  // SEARCH COMPANY
  // --------------------------------------------------
  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _companySuggestions = []);
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await _client
          .from('companies')
          .select()
          .ilike('name', '%$q%')
          .order('name')
          .limit(10);

      if (!mounted) return;

      setState(() {
        _companySuggestions = List<Map<String, dynamic>>.from(res);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
// --------------------------------------------------
// CREATE COMPANY INLINE (FROM NEW OFFER)
// --------------------------------------------------
Future<void> _createCompanyInline() async {

  final created = await showDialog<bool>(
    context: context,
    builder: (_) => const NewCompanyDialog(),
  );

  // Bruker avbrøt
  if (created != true) return;

  setState(() => _loading = true);

  try {

    // Hent siste opprettede company
    final res = await _client
        .from('companies')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .single();

    if (!mounted) return;

    // Velg automatisk
    await _select(res);

  } catch (e) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Failed to create company: $e"),
        backgroundColor: Colors.red,
      ),
    );

  } finally {

    if (mounted) {
      setState(() => _loading = false);
    }
  }
}
  // --------------------------------------------------
  // SELECT COMPANY
  // --------------------------------------------------
  Future<void> _select(Map<String, dynamic> row) async {
    final name = row['name'] ?? '';
    final id = row['id']?.toString();

    if (id == null) return;

    _currentCompanyId = id;

   setState(() {
  _companyCtrl.text = name;

  widget.offer.company = name;

  // IKKE WIPE HER
  // La bruker/DB styre dette

  _contacts.clear();
  _productions.clear();

  _contactId = null;
  _productionId = null;

  _companySuggestions.clear();
});

    await _loadDetails(id);
  }

  // --------------------------------------------------
  // LOAD CONTACTS / PRODUCTIONS
  // --------------------------------------------------
  Future<void> _loadDetails(String id) async {
    final c = await _client
        .from('contacts')
        .select()
        .eq('company_id', id)
        .order('name');

    final p = await _client
        .from('productions')
        .select()
        .eq('company_id', id)
        .order('name');

    if (!mounted) return;

    setState(() {
      _contacts = List<Map<String, dynamic>>.from(c);
      _productions = List<Map<String, dynamic>>.from(p);
    });
  }

  // --------------------------------------------------
  // RELOAD CONTACTS
  // --------------------------------------------------
  Future<void> _reloadContacts() async {
    if (_currentCompanyId == null) return;

    final c = await _client
        .from('contacts')
        .select()
        .eq('company_id', _currentCompanyId!)
        .order('name');

    if (!mounted) return;

    setState(() {
      _contacts = List<Map<String, dynamic>>.from(c);
    });
  }
// --------------------------------------------------
// PRODUCTION DIALOG
// --------------------------------------------------
Future<void> _openProductionDialog() async {
  final nameCtrl = TextEditingController();

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text("New production"),

        content: SizedBox(
          width: 360,
          child: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: "Production name",
            ),
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),

          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(ctx, name);
            },
            child: const Text("Save"),
          ),
        ],
      );
    },
  );

  if (result == null || result.isEmpty) return;

  if (_currentCompanyId == null) return;

  try {
    final saved = await _client
        .from('productions')
        .insert({
          'company_id': _currentCompanyId,
          'name': result,
        })
        .select()
        .single();

    if (!mounted) return;

    // Reload
    await _loadDetails(_currentCompanyId!);

    setState(() {
      _productionId = saved['id'].toString();
      widget.offer.production = saved['name'] ?? '';
    });

  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Save failed: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
  }

  // --------------------------------------------------
  // CONTACT DIALOG
  // --------------------------------------------------
  Future<void> _openContactDialog({Map<String, dynamic>? existing}) async {
  final nameCtrl =
      TextEditingController(text: existing?['name'] ?? '');
  final emailCtrl =
      TextEditingController(text: existing?['email'] ?? '');
  final phoneCtrl =
      TextEditingController(text: existing?['phone'] ?? '');

  final isEdit = existing != null;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(isEdit ? "Edit contact" : "New contact"),

        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Name",
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email",
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Phone",
                ),
              ),
            ],
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),

          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();

              if (name.isEmpty) return;

              try {
                Map<String, dynamic> saved;

                if (isEdit) {
                  final res = await _client
                      .from('contacts')
                      .update({
                        'name': name,
                        'email': emailCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                      })
                      .eq('id', existing!['id'])
                      .select()
                      .single();

                  saved = res;

                } else {
                  final res = await _client
                      .from('contacts')
                      .insert({
                        'company_id': _currentCompanyId,
                        'name': name,
                        'email': emailCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                      })
                      .select()
                      .single();

                  saved = res;
                }

                if (!mounted) return;

                Navigator.pop(ctx, saved);

              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Save failed: $e")),
                );
              }
            },
            child: const Text("Save"),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await _reloadContacts();

    setState(() {
  _contactId = result['id'].toString();

  widget.offer.contact = result['name'] ?? '';
  widget.offer.phone   = result['phone'] ?? '';
  widget.offer.email   = result['email'] ?? '';
});
CurrentOfferStore.set(widget.offer);
  }
}

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: constraints.maxHeight,
          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ---------- HEADER ----------
              Text(
                widget.draftId == null ? "New Offer" : "Edit Offer",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 12),

              // ---------- SCROLL ----------
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ================= COMPANY =================
                      const Text(
                        "Company",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),

                      const SizedBox(height: 6),

                      Row(
  children: [

    // ================= COMPANY SEARCH =================
    Expanded(
      child: TextField(
        controller: _companyCtrl,
        onChanged: _search,
        decoration: InputDecoration(
          labelText: "Search company",
          prefixIcon: const Icon(Icons.apartment),
          suffixIcon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ),
    ),

    const SizedBox(width: 6),

    // ================= ADD COMPANY =================
IconButton(
  tooltip: "Add new company",
  icon: const Icon(Icons.add_business),
  onPressed: _createCompanyInline,
),
],
),

if (_companySuggestions.isNotEmpty)
  Container(
    margin: const EdgeInsets.only(top: 4),
    constraints: const BoxConstraints(maxHeight: 180),
    decoration: BoxDecoration(
      color: cs.surface,
      border: Border.all(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ListView.builder(
      shrinkWrap: true,
      itemCount: _companySuggestions.length,
      itemBuilder: (_, i) {
        final c = _companySuggestions[i];

        return ListTile(
          dense: true,
          title: Text(c['name'] ?? ''),
          onTap: () => _select(c),
        );
      },
    ),
  ),

const SizedBox(height: 16),

// ================= CONTACT =================
const Text(
  "Contact",
  style: TextStyle(fontWeight: FontWeight.w900),
),

const SizedBox(height: 6),

Row(
  children: [

    Expanded(
      child: DropdownButtonFormField<String>(
        value: _contactId,
        isExpanded: true,

        items: _contacts.map((c) {
          return DropdownMenuItem(
            value: c['id'].toString(),
            child: Text(
              c['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),

        onChanged: (v) {

  final ct = _contacts.firstWhere(
    (e) => e['id'].toString() == v,
  );
final phone = ct['phone'] ?? '';
final email = ct['email'] ?? '';

setState(() {
  _contactId = v;

  widget.offer.contact = ct['name'] ?? '';
  widget.offer.phone   = phone;
  widget.offer.email   = email;

  // 🔥 SYNC TIL TEXTFIELDS
  final page =
      context.findAncestorStateOfType<_NewOfferPageState>();

  page?.phoneCtrl.text = phone;
  page?.emailCtrl.text = email;
});

  CurrentOfferStore.set(widget.offer);
}
      ),
    ),

    const SizedBox(width: 4),

    // ➕ ADD CONTACT
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: "Add contact",
      onPressed: _currentCompanyId == null
          ? null
          : () => _openContactDialog(),
    ),

    // ✏️ EDIT CONTACT
    IconButton(
      icon: const Icon(Icons.edit),
      tooltip: "Edit contact",
      onPressed: _contactId == null
          ? null
          : () {
              final c = _contacts.firstWhere(
                (e) => e['id'].toString() == _contactId,
              );

              _openContactDialog(existing: c);
            },
    ),
  ],
),

const SizedBox(height: 16),

                      // ================= PRODUCTION =================
                      // ================= PRODUCTION =================
const Text(
  "Production",
  style: TextStyle(fontWeight: FontWeight.w900),
),

const SizedBox(height: 6),

Row(
  children: [

    Expanded(
      child: DropdownButtonFormField<String>(
        value: _productionId,
        isExpanded: true,

        items: _productions.map((p) {
          return DropdownMenuItem(
            value: p['id'].toString(),
            child: Text(
              p['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),

        onChanged: (v) {
          if (v == null) return;

          final pr = _productions.firstWhere(
            (e) => e['id'].toString() == v,
          );

          setState(() {
            _productionId = v;
            widget.offer.production = pr['name'] ?? '';
          });
        },
      ),
    ),

    const SizedBox(width: 4),

    // ➕ ADD PRODUCTION
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: "Add production",
      onPressed: _currentCompanyId == null
          ? null
          : _openProductionDialog,
    ),
  ],
),
const SizedBox(height: 16),

const SizedBox(height: 12),

// ================= BUS SETTINGS =================
_BusSettingsCard(
  offer: widget.offer,
  onChanged: () {
    setState(() {});
  },
),

// ================= BUS PREVIEW (ENTERPRISE) =================
Builder(
  builder: (context) {

    // ⭐ FINN FØRSTE BUS FRA ROUNDS
    String? previewBus;

    for (final r in widget.offer.rounds) {
      if (r.bus != null && r.bus!.isNotEmpty) {
        previewBus = r.bus;
        break;
      }
    }

    return Row(
      children: [

        const Text(
          "Bus:",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),

        const SizedBox(width: 6),

        Expanded(
          child: Text(
            previewBus ?? "Not selected",
            style: const TextStyle(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        IconButton(
          tooltip: "Change bus",
          icon: const Icon(Icons.directions_bus),
          onPressed: () {
            final state =
                context.findAncestorStateOfType<_NewOfferPageState>();

            state?._changeBusManually();
          },
        ),
      ],
    );
  },
),

// ================= BUTTONS =================
Column(
  children: [

    // -------- SAVE --------
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: widget.onSave,
        icon: const Icon(Icons.save),
        label: const Text("Save draft"),
      ),
    ),

    const SizedBox(height: 8),

    // -------- SCAN PDF --------
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: widget.onScanPdf, // ✅ KORREKT
    icon: const Icon(Icons.picture_as_pdf),
    label: const Text("Scan PDF"),
  ),
),

    const SizedBox(height: 10),

    // -------- EXPORT --------
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: widget.onExport,
        icon: const Icon(Icons.download),
        label: const Text("Export PDF"),
      ),
    ),
  ],
),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  }

class _RoutesTableHeader extends StatelessWidget {
  const _RoutesTableHeader();

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 14, // 👈 STØRRE
    );

    return Row(
      children: const [
        SizedBox(
          width: 105,
          child: Text("Date", style: headerStyle),
        ),
        SizedBox(width: 12),

        Expanded(
          child: Text("Route", style: headerStyle),
        ),

        SizedBox(width: 12),

        SizedBox(
          width: 70,
          child: Text(
            "KM",
            style: headerStyle,
            textAlign: TextAlign.right,
          ),
        ),

        SizedBox(width: 10),

        SizedBox(width: 66),
      ],
    );
  }
}
class _RoutesTableRow extends StatelessWidget {
  final String date;
  final String route;
  final double? km;
  final Map<String, double> countryKm;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutesTableRow({
    required this.date,
    required this.route,
    required this.km,
    required this.countryKm,
    required this.onEdit,
    required this.onDelete,
  });

  String _buildCountryKmText() {
    if (countryKm.isEmpty) return "";

    final buffer = StringBuffer();

    countryKm.forEach((country, value) {
      if (value > 0) {
        buffer.writeln(
          "$country: ${value.toStringAsFixed(0)} km",
        );
      }
    });

    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tooltipText = _buildCountryKmText();

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 6,
      ),
      child: Row(
        children: [

          // ---------- DATE (fast prosent)
          Flexible(
            flex: 22,
            fit: FlexFit.tight,
            child: Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),

          // ---------- ROUTE (størst felt)
          Flexible(
            flex: 45,
            fit: FlexFit.tight,
            child: Text(
              route,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),

          // ---------- KM
          Flexible(
            flex: 12,
            fit: FlexFit.tight,
            child: Tooltip(
              message: tooltipText.isEmpty
                  ? "No country breakdown"
                  : tooltipText,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  km == null ? "?" : km!.toStringAsFixed(0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: km == null
                        ? cs.error
                        : cs.onSurface,
                  ),
                ),
              ),
            ),
          ),

          // ---------- BUTTONS
          Flexible(
            flex: 15,
            fit: FlexFit.tight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [

                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),

                const SizedBox(width: 4),

                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _LocationAutoComplete extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final List<String> suggestions;
  final Future<void> Function() onSubmit;
  final ValueChanged<List<String>> onPasteMulti;
  final ValueChanged<String> onQueryChanged;

  const _LocationAutoComplete({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.onSubmit,
    required this.onPasteMulti,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode, // ✅ BEHOLDER FOKUS
          decoration: const InputDecoration(
            labelText: "Location",
            prefixIcon: Icon(Icons.place),
          ),
          onSubmitted: (_) => onSubmit(),
          onChanged: (v) {
            onQueryChanged(v);

            if (v.contains("\n")) {
              final lines = v.split(RegExp(r"\r?\n"));
              controller.clear();
              onPasteMulti(lines);
            }
          },
        ),

        if (suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final s = suggestions[i];

                return ListTile(
                  dense: true,
                  title: Text(s),
                  onTap: () {
                    controller.text = s;
                    onSubmit();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
// ------------------------------------------------------------
// BUS SETTINGS WIDGET
// ------------------------------------------------------------
class _BusSettingsCard extends StatelessWidget {
  final OfferDraft offer;
  final VoidCallback onChanged;

  const _BusSettingsCard({
    required this.offer,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Bus settings",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 10),

          // ---------------- BUS COUNT ----------------
          DropdownButtonFormField<int>(
            value: offer.busCount,
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: cs.onSurface,
            ),
            decoration: const InputDecoration(
              labelText: "Buses",
              prefixIcon: Icon(Icons.directions_bus),
            ),
            items: [1, 2, 3, 4]
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Text(
                      "$n bus${n > 1 ? "es" : ""}",
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              offer.busCount = v;
              onChanged();
            },
          ),

          const SizedBox(height: 12),

          // ---------------- BUS TYPE ----------------
          DropdownButtonFormField<BusType>(
            value: offer.busType,
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: cs.onSurface,
            ),
            decoration: const InputDecoration(
              labelText: "Bus type",
              prefixIcon: Icon(Icons.airline_seat_recline_extra),
            ),
            items: BusType.values
                .map(
                  (b) => DropdownMenuItem(
                    value: b,
                    child: Text(
                      b.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              offer.busType = v;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}