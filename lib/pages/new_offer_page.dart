import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/calendar_sync_service.dart';
import '../supabase_clients.dart';

import '../models/offer_draft.dart';
import 'package:booking_desktop/services/trip_calculator.dart';
import '../services/offer_pdf_service.dart';
import '../state/settings_store.dart';
import '../widgets/offer_preview.dart';
import '../services/offer_storage_service.dart';
import 'package:go_router/go_router.dart';

// ✅ NY: bruker routes db for autocomplete + route lookup
import '../services/routes_service.dart';
import '../services/customers_service.dart';

class NewOfferPage extends StatefulWidget {
  /// ✅ Hvis du sender inn offerId -> åpner den eksisterende draft
  final String? offerId;

  const NewOfferPage({super.key, this.offerId});

  @override
  State<NewOfferPage> createState() => _NewOfferPageState();
}

class _NewOfferPageState extends State<NewOfferPage> {
  int roundIndex = 0;

  // ------------------------------------------------------------
  // BUS PICKER (Calendar sync)
  // ------------------------------------------------------------
  Future<String?> _pickBus() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Select bus"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _busTile(ctx, "CSS_1034"),
              _busTile(ctx, "CSS_1023"),
              _busTile(ctx, "CSS_1008"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Widget _busTile(BuildContext ctx, String bus) {
    return ListTile(
      leading: const Icon(Icons.directions_bus),
      title: Text(bus),
      onTap: () => Navigator.of(ctx).pop(bus),
    );
  }

  // ------------------------------------------------------------
  // DEFAULT OFFER
  // ------------------------------------------------------------
  final OfferDraft offer = OfferDraft(
    company: '',
    contact: '',
    production: '',
  );

  final TextEditingController companyCtrl = TextEditingController();
  final TextEditingController contactCtrl = TextEditingController();
  final TextEditingController productionCtrl = TextEditingController();

  final TextEditingController startLocCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();

  DateTime? selectedDate;

  // ------------------------------------------------------------
  // Draft
  // ------------------------------------------------------------
  String? _draftId;
  bool _loadingDraft = false;

  // ------------------------------------------------------------
  // Routes service
  // ------------------------------------------------------------
  final RoutesService _routesService = RoutesService();

  List<String> _locationSuggestions = [];
  bool _loadingSuggestions = false;

  SupabaseClient get sb => Supabase.instance.client;

  // ------------------------------------------------------------
  // CACHES (GLOBAL PER ROUTE)
  // ------------------------------------------------------------
  final Map<String, double?> _distanceCache = {};
  final Map<String, double> _ferryCache = {};
  final Map<String, double> _tollCache = {};
  final Map<String, String> _extraCache = {};

  // ✅ NY: Land-km cache
  final Map<String, Map<String, double>> _countryKmCache = {};

  // ------------------------------------------------------------
  // PER ENTRY (CURRENT ROUND)
  // ------------------------------------------------------------
  bool _loadingKm = false;
  String? _kmError;

  Map<int, double?> _kmByIndex = {};
  Map<int, double> _ferryByIndex = {};
  Map<int, double> _tollByIndex = {};
  Map<int, String> _extraByIndex = {};

  // ✅ NY: Land-km per entry
  Map<int, Map<String, double>> _countryKmByIndex = {};

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    companyCtrl.text = offer.company;
    contactCtrl.text = offer.contact;
    productionCtrl.text = offer.production;

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

  /// ✅ KRITISK: Når vi klikker nytt draft i dashboard mens vi allerede er på /new
  /// initState kjøres ikke igjen. Derfor må vi reagere på ny widget.offerId her.
  @override
  void didUpdateWidget(covariant NewOfferPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newId = widget.offerId?.trim();
    final oldId = oldWidget.offerId?.trim();

    // Hvis vi får ny ID -> last nytt draft
    if (newId != null && newId.isNotEmpty && newId != oldId) {
      _loadDraft(newId);
    }

    // Hvis vi går fra draft -> blank new offer
    if ((newId == null || newId.isEmpty) &&
        (oldId != null && oldId.isNotEmpty)) {
      _resetToBlankOffer();
    }
  }

  void _syncRoundControllers() {
    startLocCtrl.text = offer.rounds[roundIndex].startLocation;
    selectedDate = null;
    locationCtrl.text = '';
    _kmError = null;

    _kmByIndex = {};
    _ferryByIndex = {};
    _tollByIndex = {};
    _extraByIndex = {};
  }

  void _resetToBlankOffer() {
    setState(() {
      _draftId = null;
      roundIndex = 0;

      // reset offer til defaults
      offer.company = 'Norsk Turnétransport AS';
      offer.contact = 'Michael';
      offer.production = 'Karpe';
      offer.busCount = 1;
      offer.busType = BusType.sleeper12;

      for (final r in offer.rounds) {
        r.startLocation = '';
        r.trailer = false;
        r.pickupEveningFirstDay = false;
        r.entries.clear();
      }

      companyCtrl.text = offer.company;
      contactCtrl.text = offer.contact;
      productionCtrl.text = offer.production;

      _syncRoundControllers();
    });

    _recalcKm();
  }

  @override
  void dispose() {
    companyCtrl.dispose();
    contactCtrl.dispose();
    productionCtrl.dispose();
    startLocCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // ✅ Load existing draft
  // ------------------------------------------------------------
  Future<void> _loadDraft(String id) async {
    setState(() => _loadingDraft = true);

    try {
      final loaded = await OfferStorageService.loadDraft(id);

      // copy loaded fields into current offer
      offer.company = loaded.company;
      offer.contact = loaded.contact;
      offer.production = loaded.production;
      offer.busCount = loaded.busCount;
      offer.busType = loaded.busType;

      // rounds:
      for (int i = 0; i < offer.rounds.length; i++) {
        offer.rounds[i].startLocation = loaded.rounds[i].startLocation;
        offer.rounds[i].trailer = loaded.rounds[i].trailer;
        offer.rounds[i].pickupEveningFirstDay =
            loaded.rounds[i].pickupEveningFirstDay;

        offer.rounds[i].entries.clear();
        offer.rounds[i].entries.addAll(loaded.rounds[i].entries);
      }

      // update controllers
      companyCtrl.text = offer.company;
      contactCtrl.text = offer.contact;
      productionCtrl.text = offer.production;

      // set draftId
      _draftId = id;

      // reset UI state
      roundIndex = 0;
      _syncRoundControllers();

      if (!mounted) return;
      setState(() {});
      await _recalcKm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Load draft failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
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
  Future<void> _onAddMissingRoutePressed() async {
  // CASE 1: Draft er ikke lagret ennå
  if (_draftId == null) {
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Save draft first?"),
        content: const Text(
          "You need to save this offer before adding routes.\n\nDo you want to save now?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("No"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Yes, save"),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      await _saveDraft();
    } else {
      return;
    }
  }

  // CASE 2: Draft finnes → gå til Routes Admin
  if (!mounted) return;
  GoRouter.of(context).go("/routes");
}

  String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: selectedDate ?? now,
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  String _norm(String s) => s.trim().replaceAll(RegExp(r"\s+"), " ");
  String _cacheKey(String from, String to) =>
      "${_norm(from).toLowerCase()}__${_norm(to).toLowerCase()}";

  // ------------------------------------------------------------
  // ✅ Save draft to Supabase (insert/update)
  // ------------------------------------------------------------
  Future<void> _saveDraft() async {
  try {
    // Sørg for at startlocation er synket
    offer.rounds[roundIndex].startLocation =
        _norm(startLocCtrl.text);

    // --------------------------------------------------
    // 0️⃣ Velg buss først
    // --------------------------------------------------
    final selectedBus = await _pickBus();

    if (selectedBus == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingen buss valgt")),
      );
      return;
    }


   // 1️⃣ Lagre draft (Desktop DB)
    // --------------------------------------------------
    final id = await OfferStorageService.saveDraft(
  id: _draftId,
  offer: offer,
);

if (id == null || id.isEmpty) {
  throw Exception("Failed to save draft (no ID returned)");
}

    // --------------------------------------------------
    // 2️⃣ HENT FERSK DATA FRA DB (KRITISK)
    // --------------------------------------------------
    final freshOffer = await OfferStorageService.loadDraft(id);

if (freshOffer == null) {
  throw Exception("Draft was saved, but could not be reloaded from DB.");
}

await CalendarSyncService.syncFromOffer(
  freshOffer,
  selectedBus: selectedBus,
  draftId: id, // ✅
);

    // --------------------------------------------------

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Lagret på $selectedBus ✅")),
    );

    setState(() {});
  } catch (e, st) {
    debugPrint("SAVE ERROR:");
    debugPrint(e.toString());
    debugPrint(st.toString());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Save failed: $e")),
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
  final toN = _norm(to);
  final key = _cacheKey(fromN, toN);

  // ---------------- CACHE HIT ----------------
  if (_distanceCache.containsKey(key)) {
    _ferryByIndex[index] = _ferryCache[key] ?? 0.0;
    _tollByIndex[index] = _tollCache[key] ?? 0.0;
    _extraByIndex[index] = _extraCache[key] ?? '';

    // ✅ VIKTIG: land-cache også
    _countryKmByIndex[index] = _countryKmCache[key] ?? {};

    return _distanceCache[key];
  }

  try {
    final res = await _routesService.findRoute(
      from: fromN,
      to: toN,
    );

    if (res == null) {
      _distanceCache[key] = null;
      _ferryCache[key] = 0.0;
      _tollCache[key] = 0.0;
      _extraCache[key] = '';
      _countryKmCache[key] = {};

      _ferryByIndex[index] = 0.0;
      _tollByIndex[index] = 0.0;
      _extraByIndex[index] = '';
      _countryKmByIndex[index] = {};

      return null;
    }

    // ---------------- HOVEDDATA ----------------
    final km = (res['distance_total_km'] as num?)?.toDouble();
    final ferry = (res['ferry_price'] as num?)?.toDouble() ?? 0.0;
    final toll = (res['toll_nightliner'] as num?)?.toDouble() ?? 0.0;
    final extra = (res['extra'] as String?)?.trim() ?? '';

    // ---------------- LAND-FORDELING ----------------
    final Map<String, double> countryKm = {
      if ((res['km_dk'] as num?) != null && (res['km_dk'] as num) > 0)
        'DK': (res['km_dk'] as num).toDouble(),

      if ((res['km_de'] as num?) != null && (res['km_de'] as num) > 0)
        'DE': (res['km_de'] as num).toDouble(),

      if ((res['km_be'] as num?) != null && (res['km_be'] as num) > 0)
        'BE': (res['km_be'] as num).toDouble(),

      if ((res['km_pl'] as num?) != null && (res['km_pl'] as num) > 0)
        'PL': (res['km_pl'] as num).toDouble(),

      if ((res['km_au'] as num?) != null && (res['km_au'] as num) > 0)
        'AT': (res['km_au'] as num).toDouble(),

      if ((res['km_hr'] as num?) != null && (res['km_hr'] as num) > 0)
        'HR': (res['km_hr'] as num).toDouble(),

      if ((res['km_si'] as num?) != null && (res['km_si'] as num) > 0)
        'SI': (res['km_si'] as num).toDouble(),

      if ((res['km_other'] as num?) != null && (res['km_other'] as num) > 0)
        'Other': (res['km_other'] as num).toDouble(),
    };

    // ---------------- CACHE ----------------
    _distanceCache[key] = km;
    _ferryCache[key] = ferry;
    _tollCache[key] = toll;
    _extraCache[key] = extra;
    _countryKmCache[key] = countryKm;

    // ---------------- PER ENTRY ----------------
    _ferryByIndex[index] = ferry;
    _tollByIndex[index] = toll;
    _extraByIndex[index] = extra;
    _countryKmByIndex[index] = countryKm;

    return km;
  } catch (e) {
    _distanceCache[key] = null;
    _ferryCache[key] = 0.0;
    _tollCache[key] = 0.0;
    _extraCache[key] = '';
    _countryKmCache[key] = {};

    _ferryByIndex[index] = 0.0;
    _tollByIndex[index] = 0.0;
    _extraByIndex[index] = '';
    _countryKmByIndex[index] = {};

    return null;
  }
}

  // ------------------------------------------------------------
  // Recalculate legs for CURRENT round
  // ------------------------------------------------------------
  Future<void> _recalcKm() async {
  final round = offer.rounds[roundIndex];
  final start = _norm(round.startLocation);

  if (start.isEmpty) {
    setState(() {
      _kmByIndex = {};
      _ferryByIndex = {};
      _tollByIndex = {};
      _extraByIndex = {};
    });
    return;
  }

    final entries = [...round.entries]..sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _loadingKm = true;
      _kmError = null;
    });

    final Map<int, double?> kmByIndex = {};
    final Map<int, double> ferryByIndex = {};
    final Map<int, double> tollByIndex = {};
    final Map<int, String> extraByIndex = {};

    bool missing = false;

    for (int i = 0; i < entries.length; i++) {
      final from = i == 0 ? start : _norm(entries[i - 1].location);
      final to = _norm(entries[i].location);

      final km = await _fetchLegData(from: from, to: to, index: i);
      kmByIndex[i] = km;

      ferryByIndex[i] = _ferryByIndex[i] ?? 0.0;
      tollByIndex[i] = _tollByIndex[i] ?? 0.0;
      extraByIndex[i] = _extraByIndex[i] ?? '';

      if (km == null) missing = true;
    }

    setState(() {
  _kmByIndex = kmByIndex;
  _ferryByIndex = ferryByIndex;
  _tollByIndex = tollByIndex;
  _extraByIndex = extraByIndex;

  // ✅ LAGRE EXTRA + COUNTRY KM I ENTRY (VIKTIG FOR PDF + VAT)
for (int i = 0; i < round.entries.length; i++) {
  round.entries[i] = round.entries[i].copyWith(
    extra: extraByIndex[i] ?? '',
    countryKm: _countryKmByIndex[i] ?? {},
  );
}

  _loadingKm = false;

  if (missing) {
    _kmError = "Missing routes in routes_all. Check place names / direction.";
  }
});
  }

  // ------------------------------------------------------------
  // Add entry
  // ------------------------------------------------------------
  Future<void> _addEntry() async {
  final loc = _norm(locationCtrl.text);

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

  final nextIndex = offer.rounds[roundIndex].entries.length;

  final extra = _extraByIndex[nextIndex] ?? '';

  setState(() {
    offer.rounds[roundIndex].entries.add(
      RoundEntry(
        date: selectedDate!,
        location: loc,
        extra: extra, // ✅ HER
      ),
    );

    offer.rounds[roundIndex].entries
        .sort((a, b) => a.date.compareTo(b.date));

    // Auto next day
    selectedDate = selectedDate!.add(const Duration(days: 1));

    locationCtrl.clear();
    _locationSuggestions = [];
  });

  await _recalcKm();
}

  Future<void> _pasteManyLines(List<String> lines) async {
  if (selectedDate == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pick a date first, then paste.")),
    );
    return;
  }

  final clean = lines.map(_norm).where((e) => e.isNotEmpty).toList();
  if (clean.isEmpty) return;

  setState(() {
    for (final loc in clean) {
      final idx = offer.rounds[roundIndex].entries.length;

      final extra = _extraByIndex[idx] ?? '';

      offer.rounds[roundIndex].entries.add(
        RoundEntry(
          date: selectedDate!,
          location: loc,
          extra: extra, // ✅ HER
        ),
      );

      selectedDate = selectedDate!.add(const Duration(days: 1));
    }

    offer.rounds[roundIndex].entries
        .sort((a, b) => a.date.compareTo(b.date));

    locationCtrl.clear();
    _locationSuggestions = [];
  });

  await _recalcKm();
}

  Future<void> _editEntry(int index) async {
    final entry = offer.rounds[roundIndex].entries[index];
    DateTime tempDate = entry.date;
    final tempLocCtrl = TextEditingController(text: entry.location);

    final updated = await showDialog<RoundEntry>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(builder: (_, setDialogState) {
          return AlertDialog(
            title: const Text("Edit entry"),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_fmtDate(tempDate)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogCtx,
                        firstDate: DateTime(tempDate.year - 1),
                        lastDate: DateTime(tempDate.year + 5),
                        initialDate: tempDate,
                      );
                      if (picked != null) setDialogState(() => tempDate = picked);
                    },
                  ),
                  const SizedBox(height: 10),
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
                  Navigator.of(context, rootNavigator: true).pop(),
                child: const Text("Cancel"),
),
              FilledButton(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop(
                    RoundEntry(
                      date: tempDate,
                      location: _norm(tempLocCtrl.text),
                      extra: entry.extra,
  ),
);
                },
                child: const Text("Save"),
              ),
            ],
          );
        });
      },
    );

    if (updated == null) return;

    setState(() {
      offer.rounds[roundIndex].entries[index] = updated;
      offer.rounds[roundIndex].entries.sort((a, b) => a.date.compareTo(b.date));
    });

    await _recalcKm();
  }

  // ------------------------------------------------------------
  // ✅ Per-round calc helper (used for PDF for ALL rounds)
  // ------------------------------------------------------------
  Future<RoundCalcResult> _calcRound(int ri) async {
    final round = offer.rounds[ri];
    final entryCount = round.entries
      .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
      .toSet()
      .length;

    if (entryCount == 0) {
      return TripCalculator.calculateRound(
        settings: SettingsStore.current,
        entryCount: 0,
        pickupEveningFirstDay: false,
        trailer: round.trailer,
        totalKm: 0.0,
        legKm: const [],
        ferryCost: 0.0,
        tollCost: 0.0,
      );
    }

    final start = _norm(round.startLocation);
    final entries = [...round.entries]..sort((a, b) => a.date.compareTo(b.date));

    final Map<int, double?> kmByIndex = {};
    final Map<int, double> ferryByIndex = {};
    final Map<int, double> tollByIndex = {};

    for (int i = 0; i < entries.length; i++) {
      final from = i == 0 ? start : _norm(entries[i - 1].location);
      final to = _norm(entries[i].location);

      final km = await _fetchLegData(from: from, to: to, index: i);
      kmByIndex[i] = km;

      ferryByIndex[i] = _ferryByIndex[i] ?? 0.0;
      tollByIndex[i] = _tollByIndex[i] ?? 0.0;
    }

    final totalKm =
        kmByIndex.values.whereType<double>().fold<double>(0, (a, b) => a + b);
    final legKm =
        List.generate(entryCount, (i) => (kmByIndex[i] ?? 0.0).toDouble());

    final ferryTotal = ferryByIndex.values.fold<double>(0.0, (a, b) => a + b);
    final tollTotal = tollByIndex.values.fold<double>(0.0, (a, b) => a + b);

    return TripCalculator.calculateRound(
      settings: SettingsStore.current,
      entryCount: entryCount,
      pickupEveningFirstDay: round.pickupEveningFirstDay,
      trailer: round.trailer,
      totalKm: totalKm,
      legKm: legKm,
      ferryCost: ferryTotal,
      tollCost: tollTotal,
    );
  }

  // ------------------------------------------------------------
  // ✅ Build PDF bytes
  // ------------------------------------------------------------
  Future<Uint8List> _buildPdfBytes() async {
    final Map<int, RoundCalcResult> calcByRound = {};

    for (int i = 0; i < offer.rounds.length; i++) {
      final r = offer.rounds[i];
      final has = r.entries.isNotEmpty || r.startLocation.trim().isNotEmpty;
      if (!has) continue;

      final calc = await _calcRound(i);
      calcByRound[i] = calc;
    }

    return OfferPdfService.buildPdf(
      offer: offer,
      settings: SettingsStore.current,
      roundCalcByIndex: calcByRound,
    );
  }

  // ------------------------------------------------------------
  // ✅ Export PDF
  // ------------------------------------------------------------
  Future<void> _exportPdf() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 70,
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text("Generating PDF...")),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await _buildPdfBytes().timeout(const Duration(seconds: 30));
      final filePath = await _savePdfToFile(bytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF saved:\n$filePath")),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF export failed: $e")),
      );
    }
  }

  // ------------------------------------------------------------
  // ✅ Save PDF (FilePicker)
  // ------------------------------------------------------------
  Future<String> _savePdfToFile(Uint8List bytes) async {
    final production = offer.production.trim().isEmpty
        ? "UnknownProduction"
        : offer.production.trim();
    final safeProduction = _safeFolderName(production);

    final todayStamp = DateFormat("yyyyMMdd").format(DateTime.now());
    final defaultFileName = "Offer Nightliner $safeProduction $todayStamp.pdf";

    final filePath = await FilePicker.platform.saveFile(
      dialogTitle: "Save PDF offer",
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ["pdf"],
      lockParentWindow: true,
    );

    if (filePath == null) {
      throw Exception("Save cancelled.");
    }

    var finalPath = filePath;
    if (!finalPath.toLowerCase().endsWith(".pdf")) {
      finalPath += ".pdf";
    }

    final file = File(finalPath);
    await file.writeAsBytes(bytes, flush: true);

    return finalPath;
  }

  String _safeFolderName(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'[\/\\\:\*\?\"\<\>\|]'), "_");
    s = s.replaceAll(RegExp(r"\s+"), " ");
    return s;
  }

  String _nok(double v) => "${v.toStringAsFixed(0)},-";

    // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final round = offer.rounds[roundIndex];

    final entryCount = round.entries
        .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
        .toSet()
        .length;

    final totalKm =
        _kmByIndex.values.whereType<double>().fold<double>(0, (a, b) => a + b);

    final ferryTotal =
        _ferryByIndex.values.fold<double>(0.0, (a, b) => a + b);

    final tollTotal =
        _tollByIndex.values.fold<double>(0.0, (a, b) => a + b);

    final calc = TripCalculator.calculateRound(
      settings: SettingsStore.current,
      entryCount: entryCount,
      pickupEveningFirstDay: round.pickupEveningFirstDay,
      trailer: round.trailer,
      totalKm: totalKm,
      legKm: _kmByIndex.values
          .whereType<double>()
          .map((e) => e.toDouble())
          .toList(),
      ferryCost: ferryTotal,
      tollCost: tollTotal,
    );

    final basePrice =
        calc.totalCost - calc.ferryCost - calc.tollCost;

    final countryKm = _collectAllCountryKm();

    final foreignVatMap = _calculateForeignVat(
      basePrice: basePrice,
      countryKm: countryKm,
    );

    final totalExVat = calc.totalCost;

    final totalIncVat = totalExVat +
        foreignVatMap.values.fold(0.0, (a, b) => a + b);

    if (_loadingDraft) {
      return const Center(child: CircularProgressIndicator());
    }

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
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: round.pickupEveningFirstDay,
                            onChanged: (v) async {
                              setState(() {
                                round.pickupEveningFirstDay = v ?? false;
                              });

                              await _recalcKm();
                            },
                          ),
                          const Text(
                              "Pickup evening (first day not billable)"),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: round.trailer,
                            onChanged: (v) {
                              setState(() {
                                round.trailer = v ?? false;
                              });
                            },
                          ),
                          const Text("Trailer"),
                        ],
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
                          suggestions: _locationSuggestions,
                          onSubmit: _addEntry,
                          onPasteMulti: _pasteManyLines,
                          onQueryChanged: _loadPlaceSuggestions,
                        ),

                        const SizedBox(height: 8),

                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_road),
                          label: const Text("Add missing route"),
                          onPressed: _onAddMissingRoutePressed,
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
                      padding:
                          const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: cs.outlineVariant),
                        color: cs.surface,
                      ),
                      child: Column(
                        children: [

                          const _RoutesTableHeader(),

                          Divider(
                            height: 14,
                            color: cs.outlineVariant,
                          ),

                          if (round.entries.isEmpty)
                            const Expanded(
                              child: Center(
                                child: Text("No entries yet."),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                itemCount: round.entries.length,
                                separatorBuilder: (_, __) =>
                                    Divider(
                                  height: 1,
                                  color: cs.outlineVariant,
                                ),
                                itemBuilder: (_, i) {
                                  final e = round.entries[i];
                                  final km = _kmByIndex[i];

                                  final from = i == 0
                                      ? round.startLocation
                                      : round.entries[i - 1]
                                          .location;

                                  final routeText =
                                      "${_norm(from)} → ${_norm(e.location)}";

                                  return _RoutesTableRow(
                                    date: _fmtDate(e.date),
                                    route: routeText,
                                    km: km,
                                    countryKm:
                                        _countryKmByIndex[i] ?? {},
                                    onEdit: () => _editEntry(i),
                                    onDelete: () async {
                                      setState(() {
                                        offer.rounds[roundIndex]
                                            .entries
                                            .removeAt(i);
                                      });

                                      await _recalcKm();
                                    },
                                  );
                                },
                              ),
                            ),

                          Divider(
                            height: 14,
                            color: cs.outlineVariant,
                          ),

                          // ---------- SUMMARY ----------
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              Text(
                                "Billable days: ${calc.billableDays}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                "Included: ${calc.includedKm.toStringAsFixed(0)} km",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                "Extra: ${calc.extraKm.toStringAsFixed(0)} km",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                "Total: ${totalKm.toStringAsFixed(0)} km",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // ---------- COST ----------
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: cs.outlineVariant),
                              color:
                                  cs.surfaceContainerLowest,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [

                                Wrap(
                                  spacing: 16,
                                  runSpacing: 6,
                                  children: [
                                    Text(
                                      "Days: ${_nok(calc.dayCost)}",
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w900),
                                    ),
                                    Text(
                                      "Extra km: ${_nok(calc.extraKmCost)}",
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w900),
                                    ),
                                    if (calc.dDriveDays > 0)
                                      Text(
                                        "D.Drive (${calc.dDriveDays}): ${_nok(calc.dDriveCost)}",
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w900),
                                      ),
                                    if (round.trailer)
                                      Text(
                                        "Trailer: ${_nok(calc.trailerDayCost + calc.trailerKmCost)}",
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w900),
                                      ),
                                    if (ferryTotal > 0)
                                      Text(
                                        "Ferry: ${_nok(calc.ferryCost)}",
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w900),
                                      ),
                                    if (tollTotal > 0)
                                      Text(
                                        "Toll: ${_nok(calc.tollCost)}",
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w900),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                Align(
                                  alignment:
                                      Alignment.centerRight,
                                  child: Text(
                                    "TOTAL: ${_nok(calc.totalCost)}",
                                    style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),

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

                    OfferPreview(offer: offer),

                    const SizedBox(height: 20),

                    // ---------- VAT ----------
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [

                          const Text(
                            "VAT summary",
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.w900,
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
  final String? draftId;

  const _LeftOfferCard({
    super.key,
    required this.offer,
    required this.onExport,
    required this.onSave,
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
      widget.offer.contact = '';
      widget.offer.production = '';

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

    final saved = await showDialog<bool>(
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),

            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();

                if (name.isEmpty) return;

                try {
                  if (isEdit) {
                    await _client
                        .from('contacts')
                        .update({
                          'name': name,
                          'email': emailCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                        })
                        .eq('id', existing!['id']);
                  } else {
                    await _client.from('contacts').insert({
                      'company_id': _currentCompanyId,
                      'name': name,
                      'email': emailCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                    });
                  }

                  if (!mounted) return;

                  Navigator.pop(ctx, true);
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

    if (saved == true) {
      await _reloadContacts();
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

                      TextField(
                        controller: _companyCtrl,
                        onChanged: _search,
                        decoration: InputDecoration(
                          labelText: "Search company",
                          prefixIcon: const Icon(Icons.apartment),
                          suffixIcon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                        ),
                      ),

                      if (_companySuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints:
                              const BoxConstraints(maxHeight: 180),
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
                                if (v == null) return;

                                final ct = _contacts.firstWhere(
                                  (e) => e['id'].toString() == v,
                                );

                                setState(() {
                                  _contactId = v;
                                  widget.offer.contact =
                                      ct['name'] ?? '';
                                });
                              },
                            ),
                          ),

                          const SizedBox(width: 4),

                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: "Add contact",
                            onPressed: _currentCompanyId == null
                                ? null
                                : () => _openContactDialog(),
                          ),

                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: "Edit contact",
                            onPressed: _contactId == null
                                ? null
                                : () {
                                    final c = _contacts.firstWhere(
                                      (e) =>
                                          e['id'].toString() ==
                                          _contactId,
                                    );

                                    _openContactDialog(existing: c);
                                  },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ================= PRODUCTION =================
                      const Text(
                        "Production",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),

                      const SizedBox(height: 6),

                      DropdownButtonFormField<String>(
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
                            widget.offer.production =
                                pr['name'] ?? '';
                          });
                        },
                      ),

                      const SizedBox(height: 18),

                      // ================= BUS =================
                      _BusSettingsCard(
                        offer: widget.offer,
                        onChanged: () => setState(() {}),
                      ),

                      const SizedBox(height: 20),

                      Divider(color: cs.outlineVariant),

                      const SizedBox(height: 16),

                      // ================= BUTTONS =================
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onSave,
                              icon: const Icon(Icons.save),
                              label: const Text("Save draft"),
                            ),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: FilledButton.icon(
                              onPressed: widget.onExport,
                              icon: const Icon(Icons.picture_as_pdf),
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
  final List<String> suggestions;
  final Future<void> Function() onSubmit;
  final ValueChanged<List<String>> onPasteMulti;
  final ValueChanged<String> onQueryChanged;

  const _LocationAutoComplete({
    required this.controller,
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