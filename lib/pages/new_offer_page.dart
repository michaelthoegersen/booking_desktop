

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
import '../services/invoice_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/email_service.dart';

// ✅ NY: bruker routes db for autocomplete + route lookup
import '../services/routes_service.dart';
import '../services/km_se_updater.dart';
import '../services/customers_service.dart';
import '../state/current_offer_store.dart';
import '../models/round_calc_result.dart';
import '../models/swe_calc_result.dart';
import '../services/swe_calculator.dart';
import '../services/ferry_resolver.dart';
import 'package:flutter/foundation.dart';
import '../platform/pdf_saver.dart';
import '../utils/bus_utils.dart';
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
    builder: (dialogCtx) => AlertDialog(
      title: const Text("Select bus"),
      content: SizedBox(
        width: 300,
        child: ListView(
          shrinkWrap: true,
          children: [
            ...buses.map((bus) {
              return ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text(fmtBus(bus)),
                onTap: () => Navigator.pop(dialogCtx, bus),
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.hourglass_top_outlined,
                color: Colors.orange,
              ),
              title: const Text(
                "Waiting list",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(dialogCtx, "WAITING_LIST"),
            ),
          ],
        ),
      ),
    ),
  );
}


  // ===================================================
  // STATE FIELDS
  // ===================================================

  int roundIndex = 0;

  bool _calcExpanded  = false;
  bool _totalExpanded = false;

  /// Tracks the DB status before the current save — used to detect the
  /// transition to 'Confirmed' so the ferry email fires exactly once.
  String? _savedStatus;

  bool _busLoaded = false;

  final FocusNode _locationFocus = FocusNode();

  final Map<int, RoundCalcResult> _roundCalcCache = {};
  final Map<int, SweCalcResult> _sweCalcCache = {};

  // Total price override (double-tap to edit)
  double? _totalOverride;
  bool _editingTotal = false;
  final TextEditingController _overrideCtrl = TextEditingController();

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
Map<int, bool> _noDDriveByIndex = {};
/// true when km_se was NULL in DB (not yet computed by KmSeUpdater).
/// Distinct from km_se = 0 (confirmed non-Swedish route).
Map<int, bool> _kmSeNullByIndex = {};

// Global caches (per route)
final Map<String, double?> _distanceCache = {};
final Map<String, bool> _noDDriveCache = {};
final Map<String, double> _ferryCache = {};
final Map<String, double> _tollCache = {};
final Map<String, String> _extraCache = {};
final Map<String, String> _ferryNameCache = {};
Map<int, String> _ferryNameByIndex = {};
final Map<String, Map<String, double>> _countryKmCache = {};
/// Cached per-route: was km_se NULL in DB at last fetch?
final Map<String, bool> _kmSeNullCache = {};
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
      b.writeln("Toll:  ${_nok(r.tollCost)}");
    }

    // ================= TOTAL =================

    b.writeln("");
    b.writeln("----------------------------");
    b.writeln("TOTAL: ${_nok(r.totalCost)}");

    return b.toString();
  }

  // ===================================================
  // TOTAL BREAKDOWN (all rounds)
  // ===================================================

  String _buildTotalBreakdown(AppSettings s) {
    final usedEntries = _roundCalcCache.entries
        .where((e) => offer.rounds[e.key].entries.isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (usedEntries.isEmpty) return "No rounds calculated yet.";

    final b = StringBuffer();

    double totalDayCost      = 0;
    double totalExtraKmCost  = 0;
    double totalDDriveCost   = 0;
    double totalTrailerCost  = 0;
    double totalFerryCost    = 0;
    double totalFlightCost   = 0;
    double totalTollCost     = 0;
    double grandTotal        = 0;

    for (final entry in usedEntries) {
      final ri    = entry.key;
      final r     = entry.value;
      final round = offer.rounds[ri];

      final buses = round.busSlots
          .whereType<String>()
          .where((x) => x.isNotEmpty)
          .map(fmtBus)
          .join(', ');
      final busLabel = buses.isNotEmpty ? buses : 'No bus';

      b.writeln("ROUND ${ri + 1}  ($busLabel)");
      b.writeln("----------------------------");

      b.writeln(
        "  Days:     ${r.billableDays} × ${_nok(s.dayPrice)}"
        " = ${_nok(r.dayCost)}",
      );

      b.writeln(
        "  KM:       ${(r.includedKm + r.extraKm).toStringAsFixed(0)} km"
        "  (incl ${r.includedKm.toStringAsFixed(0)} km)",
      );

      if (r.extraKm > 0) {
        b.writeln(
          "  Extra km: ${r.extraKm.toStringAsFixed(0)} × ${_nok(s.extraKmPrice)}"
          " = ${_nok(r.extraKmCost)}",
        );
      }

      if (r.dDriveDays > 0) {
        b.writeln(
          "  D.Drive:  ${r.dDriveDays} × ${_nok(s.dDriveDayPrice)}"
          " = ${_nok(r.dDriveCost)}",
        );
      }

      final trailerTotal = r.trailerDayCost + r.trailerKmCost;
      if (trailerTotal > 0) b.writeln("  Trailer:  ${_nok(trailerTotal)}");
      if (r.ferryCost   > 0) b.writeln("  Ferry:    ${_nok(r.ferryCost)}");
      if (r.flightCost  > 0) b.writeln("  Flights:  ${_nok(r.flightCost)}");
      if (r.tollCost    > 0) b.writeln("  Toll:     ${_nok(r.tollCost)}");

      b.writeln("  Round total: ${_nok(r.totalCost)}");
      b.writeln();

      totalDayCost     += r.dayCost;
      totalExtraKmCost += r.extraKmCost;
      totalDDriveCost  += r.dDriveCost;
      totalTrailerCost += trailerTotal;
      totalFerryCost   += r.ferryCost;
      totalFlightCost  += r.flightCost;
      totalTollCost    += r.tollCost;
      grandTotal       += r.totalCost;
    }

    b.writeln("============================");
    b.writeln("SUBTOTALS");
    b.writeln("----------------------------");
    if (totalDayCost     > 0) b.writeln("  Days:     ${_nok(totalDayCost)}");
    if (totalExtraKmCost > 0) b.writeln("  Extra km: ${_nok(totalExtraKmCost)}");
    if (totalDDriveCost  > 0) b.writeln("  D.Drive:  ${_nok(totalDDriveCost)}");
    if (totalTrailerCost > 0) b.writeln("  Trailer:  ${_nok(totalTrailerCost)}");
    if (totalFerryCost   > 0) b.writeln("  Ferry:    ${_nok(totalFerryCost)}");
    if (totalFlightCost  > 0) b.writeln("  Flights:  ${_nok(totalFlightCost)}");
    if (totalTollCost    > 0) b.writeln("  Toll:     ${_nok(totalTollCost)}");
    b.writeln("----------------------------");

    if (_totalOverride != null) {
      b.writeln("  Calculated: ${_nok(grandTotal)}");
      b.writeln("  Override:   ${_nok(_totalOverride!)}");
      b.writeln("GRAND TOTAL: ${_nok(_totalOverride!)}");
    } else {
      b.writeln("GRAND TOTAL: ${_nok(grandTotal)}");
    }

    return b.toString();
  }

// ---------------------------------------------------
// Recalculate all rounds (for PDF + totals)
// ---------------------------------------------------
Future<void> _recalcAllRounds() async {
  // Pre-fetch legs for ALL rounds in parallel before calculating.
  // Rounds that share routes benefit from a single DB call.
  await Future.wait([
    for (final r in offer.rounds)
      if (r.entries.isNotEmpty)
        _prefetchLegsParallel(r.entries, _norm(r.startLocation)),
  ]);

  final Map<int, RoundCalcResult> newCache = {};
  _sweCalcCache.clear();

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

  final busyList = allBuses.where((b) => busySet.contains(b)).toList();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Select available bus"),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            // Available buses
            ...available.map((bus) {
              return ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text(fmtBus(bus)),
                onTap: () => Navigator.pop(dialogContext, bus),
              );
            }),
            // Busy buses (greyed out, unselectable)
            if (busyList.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  "Busy",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ...busyList.map((bus) {
                return ListTile(
                  enabled: false,
                  leading: Icon(
                    Icons.directions_bus,
                    color: Colors.grey.shade400,
                  ),
                  title: Text(
                    fmtBus(bus),
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                );
              }),
            ],
            const Divider(),
            // Waiting list option
            ListTile(
              leading: const Icon(
                Icons.hourglass_top_outlined,
                color: Colors.orange,
              ),
              title: const Text(
                "Waiting list",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(dialogContext, "WAITING_LIST"),
            ),
          ],
        ),
      ),
    ),
  );
}


  // ===================================================
  // GLOBAL BUS PICKER (availability across all rounds)
  // ===================================================

  Future<String?> _pickBusGlobal(int slotIndex) async {
    // Collect union date range from all active rounds
    DateTime? earliest;
    DateTime? latest;

    for (final r in offer.rounds) {
      if (r.entries.isEmpty) continue;
      final sorted = [...r.entries]..sort((a, b) => a.date.compareTo(b.date));
      final s = sorted.first.date;
      final e = sorted.last.date;
      if (earliest == null || s.isBefore(earliest)) earliest = s;
      if (latest == null || e.isAfter(latest)) latest = e;
    }

    // No dates yet — fall back to simple picker
    if (earliest == null || latest == null) {
      return _pickBusSimple();
    }

    final start = earliest.toIso8601String().substring(0, 10);
    final end = latest.toIso8601String().substring(0, 10);

    // Query busy buses across the full period
    final busy = await Supabase.instance.client
        .from('samletdata')
        .select('kilde,draft_id')
        .gte('dato', start)
        .lte('dato', end);

    final busySet = (busy as List)
        .where((e) {
          final draft = e['draft_id']?.toString();
          if (_draftId != null && draft == _draftId) return false;
          return true;
        })
        .map((e) => e['kilde']?.toString())
        .whereType<String>()
        .toSet();

    if (!mounted) return null;

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

    final available = allBuses.where((b) => !busySet.contains(b)).toList();
    final busyList = allBuses.where((b) => busySet.contains(b)).toList();

    // Suggest: first available bus not already used in another global slot
    final usedGlobal = {
      for (int j = 0; j < offer.globalBusSlots.length; j++)
        if (j != slotIndex && offer.globalBusSlots[j] != null)
          offer.globalBusSlots[j]!,
    };

    final suggested =
        available.where((b) => !usedGlobal.contains(b)).firstOrNull;

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return AlertDialog(
          title: Text("Bus ${slotIndex + 1} — all rounds"),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                ...available.map((bus) {
                  final isSuggested = bus == suggested;
                  return ListTile(
                    leading: Icon(
                      Icons.directions_bus,
                      color: isSuggested ? cs.primary : null,
                    ),
                    title: Row(
                      children: [
                        Text(fmtBus(bus)),
                        if (isSuggested) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "Suggested",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () => Navigator.pop(dialogCtx, bus),
                  );
                }),
                if (busyList.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      "Busy",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  ...busyList.map(
                    (bus) => ListTile(
                      enabled: false,
                      leading: Icon(
                        Icons.directions_bus,
                        color: Colors.grey.shade400,
                      ),
                      title: Text(
                        fmtBus(bus),
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.hourglass_top_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text(
                    "Waiting list",
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.pop(dialogCtx, "WAITING_LIST"),
                ),
              ],
            ),
          ),
        );
      },
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

  /// True while this page is mid-save so we ignore our own draftSaved event
  bool _selfSaving = false;
  StreamSubscription<String>? _draftSavesSub;

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

    // Reload when another tab saves this same draft (e.g. calendar assigns a bus)
    _draftSavesSub = OfferStorageService.draftSaved.listen((savedId) {
      if (!_selfSaving && mounted && savedId == _draftId) {
        _loadDraft(savedId);
      }
    });

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
    _draftSavesSub?.cancel();
    _overrideCtrl.dispose();
    super.dispose();
  }

  // ===================================================
  // HELPERS
  // ===================================================
  AppSettings _effectiveSettings() {
  final global = SettingsStore.current;
  final o = offer.pricingOverride;

  if (o == null) return global;

  return global.copyWith(
    dayPrice: o.dayPrice,
    extraKmPrice: o.extraKmPrice,
    trailerDayPrice: o.trailerDayPrice,
    trailerKmPrice: o.trailerKmPrice,
    dDriveDayPrice: o.dDriveDayPrice,
    flightTicketPrice: o.flightTicketPrice,
  );
}

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
  // DELETE ROUND (shifts rounds below up by one)
  // ===================================================
  Future<void> _deleteRound(int index) async {
    setState(() {
      // Shift every round from index+1 onward one position down.
      for (int i = index; i < offer.rounds.length - 1; i++) {
        final src = offer.rounds[i + 1];
        final dst = offer.rounds[i];

        dst.startLocation = src.startLocation;
        dst.trailer = src.trailer;
        dst.pickupEveningFirstDay = src.pickupEveningFirstDay;
        dst.bus = src.bus;
        dst.busSlots = List<String?>.from(src.busSlots);
        dst.trailerSlots = List<bool>.from(src.trailerSlots);
        dst.ferryPerLeg = List<String?>.from(src.ferryPerLeg);
        dst.entries
          ..clear()
          ..addAll(src.entries.map((e) => RoundEntry(
                date: e.date,
                location: e.location,
                extra: e.extra,
              )));
      }

      // Clear the last round.
      final last = offer.rounds.last;
      last.startLocation = '';
      last.trailer = false;
      last.pickupEveningFirstDay = false;
      last.bus = null;
      last.busSlots = [null, null, null, null];
      last.trailerSlots = [false, false, false, false];
      last.ferryPerLeg = [];
      last.entries.clear();

      // If the active round was at or beyond the deleted index, move it back.
      if (roundIndex >= index && roundIndex > 0) {
        roundIndex = roundIndex - 1;
      }
      _syncRoundControllers();
    });

    await _recalcKm();
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
      _savedStatus     = fresh.status;
      offer.pricingOverride = fresh.pricingOverride;
      // ⭐ ENTERPRISE: global bus brukes ikke lenger
      // offer.bus = fresh.bus;   <-- kan beholdes om legacy trengs

      offer.busCount      = fresh.busCount;
      offer.busType       = fresh.busType;
      offer.pricingModel  = fresh.pricingModel;
      offer.globalBusSlots = List.from(fresh.globalBusSlots);

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

        dst.bus = src.bus;

// ⭐⭐⭐ DETTE MANGLER ⭐⭐⭐
dst.busSlots = List.from(src.busSlots);
dst.trailerSlots = List.from(src.trailerSlots);

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
      _totalOverride = fresh.totalOverride;

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
// ✅ WAITING LIST — sync after save
//    Reads all busSlots with "WAITING_LIST" and writes to DB
// ------------------------------------------------------------
Future<void> _syncWaitingListAfterSave() async {
  if (_draftId == null) return;
  try {
    // Clear all existing entries for this draft
    await sb.from('waiting_list').delete().eq('draft_id', _draftId!);

    // Re-create for every WAITING_LIST slot
    final rows = <Map<String, dynamic>>[];

    for (int ri = 0; ri < offer.rounds.length; ri++) {
      final round = offer.rounds[ri];
      if (round.entries.isEmpty) continue; // skip rounds with no dates

      for (int si = 0; si < round.busSlots.length; si++) {
        if (round.busSlots[si] != "WAITING_LIST") continue;

        final dates = round.entries.map((e) => e.date);
        final dateFrom = dates.reduce((a, b) => a.isBefore(b) ? a : b);
        final dateTo = dates.reduce((a, b) => a.isAfter(b) ? a : b);

        rows.add({
          'draft_id': _draftId,
          'round_index': ri,
          'slot_index': si,
          'production': offer.production.trim().isEmpty
              ? 'Unnamed'
              : offer.production.trim(),
          'company': offer.company.trim().isEmpty
              ? null
              : offer.company.trim(),
          'contact': offer.contact.trim().isEmpty
              ? null
              : offer.contact.trim(),
          'date_from': dateFrom.toIso8601String().substring(0, 10),
          'date_to': dateTo.toIso8601String().substring(0, 10),
        });
      }
    }

    if (rows.isNotEmpty) {
      await sb.from('waiting_list').insert(rows);
    }
  } catch (e) {
    debugPrint('Waiting list sync error: $e');
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
  Future<void> _openMissingRouteDialog({
  String? from,
  String? to,
}) async {

  final fromCtrl = TextEditingController(text: from ?? '');
  final toCtrl = TextEditingController(text: to ?? '');
  final kmCtrl = TextEditingController();
  final extraCtrl = TextEditingController();

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
                final inserted = await sb.from('routes_all').insert({
  'from_place': from,
  'to_place': to,
  'distance_total_km': km,
  'extra': extra,
}).select('id').single();

final newId = inserted['id'] as String;

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

                // ---------------- KM SE (background) ----------------
                KmSeUpdater.computeAndSaveOne(
                  id: newId,
                  from: from,
                  to: to,
                ).then((sweKm) {
                  if (sweKm != null && mounted) _recalcKm();
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

    if (loc == 'travel') {
      return true;   // only Travel triggers the 1200km threshold
    }

    if (loc.isNotEmpty) {
      return false;  // Off or any real city stops the search → normal 600km threshold
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
    "Invoiced",
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

    case 'invoiced':
      return 'Invoiced';

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
    // Excel formula: (price/[100+rate])*rate = price * rate/(1+rate)
    // Treats basePrice as gross (VAT-inclusive); extracts the VAT component.
    final vat = basePrice * share * rate / (1 + rate);

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
  double excl,  // always the calculated value
  double incl, {
  String Function(double)? fmt,
}) {
  final f = fmt ?? _nok;
  final vatTotal = vatMap.values.fold(0.0, (a, b) => a + b);
  final displayedExcl = _totalOverride ?? excl;
  final displayedIncl = displayedExcl + vatTotal;
  final hasOverride = _totalOverride != null;

  Widget totalExclWidget = _buildEditableTotal(
    label: "Total excl VAT",
    calculatedValue: excl,
    displayedValue: displayedExcl,
    hasOverride: hasOverride,
    vatTotal: vatTotal,
    fmt: f,
  );

  if (vatMap.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        totalExclWidget,
        const SizedBox(height: 4),
        Text(
          "Total incl VAT: ${f(displayedIncl)}",
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
          "${e.key} (${rate.toStringAsFixed(1)}%): ${f(e.value)}",
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
      }),

      const SizedBox(height: 6),

      Text(
        "Total VAT: ${f(vatTotal)}",
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),

      const Divider(),

      totalExclWidget,

      const SizedBox(height: 4),

      Text(
        "Total incl VAT: ${f(displayedIncl)}",
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ],
  );
}

Widget _buildEditableTotal({
  required String label,
  required double calculatedValue,
  required double displayedValue,
  required bool hasOverride,
  required double vatTotal,
  String Function(double)? fmt,
}) {
  final f = fmt ?? _nok;
  if (_editingTotal) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w900)),
        SizedBox(
          width: 120,
          height: 32,
          child: TextField(
            controller: _overrideCtrl,
            autofocus: true,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            onSubmitted: (val) {
              final trimmed = val.trim().replaceAll(',', '.');
              final parsed = double.tryParse(trimmed);
              setState(() {
                _totalOverride = parsed; // null if empty → reverts
                _editingTotal = false;
              });
            },
            onTapOutside: (_) {
              final trimmed = _overrideCtrl.text.trim().replaceAll(',', '.');
              final parsed = double.tryParse(trimmed);
              setState(() {
                _totalOverride = parsed;
                _editingTotal = false;
              });
            },
          ),
        ),
      ],
    );
  }

  return GestureDetector(
    onDoubleTap: () {
      _overrideCtrl.text = hasOverride
          ? displayedValue.toStringAsFixed(0)
          : calculatedValue.toStringAsFixed(0);
      setState(() => _editingTotal = true);
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$label: ${f(displayedValue)}",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 4),
            const Tooltip(
              message: "Double-click to override",
              child: Icon(Icons.edit, size: 13, color: Colors.grey),
            ),
          ],
        ),
        if (hasOverride)
          Text(
            "Calculated: ${f(calculatedValue)}",
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    ),
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

  _selfSaving = true;
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
      offer.pricingOverride = current.pricingOverride;

      // ✅ VIKTIG: SYNC ROUNDS (inkl trailer)
      for (int i = 0; i < offer.rounds.length; i++) {
        if (i >= current.rounds.length) break;

        offer.rounds[i].trailer =
            current.rounds[i].trailer;

        offer.rounds[i].pickupEveningFirstDay =
            current.rounds[i].pickupEveningFirstDay;
            offer.rounds[i].busSlots =
    List.from(current.rounds[i].busSlots);

offer.rounds[i].trailerSlots =
    List.from(current.rounds[i].trailerSlots);

offer.rounds[i].bus =
    current.rounds[i].bus;
      }
    }

    // ----------------------------------------
    // Save to DB
    // ----------------------------------------
    // Capture pre-save status to detect Confirmed transition
    final statusBeforeSave = _savedStatus;

    offer.totalOverride = _totalOverride;

    // Compute total excl. VAT to persist (override takes priority)
    double calcTotal = 0;
    for (int i = 0; i < offer.rounds.length; i++) {
      final r = _roundCalcCache[i];
      if (r != null) calcTotal += r.totalCost;
    }
    final totalExclVat = _totalOverride ?? (calcTotal > 0 ? calcTotal : null);

    final id = await OfferStorageService.saveDraft(
      id: _draftId,
      offer: offer,
      totalExclVat: totalExclVat,
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
    _savedStatus     = freshOffer.status;
    offer.busCount   = freshOffer.busCount;
    offer.busType    = freshOffer.busType;

    // 🔥 GLOBAL BUS ER FJERNET (enterprise multi-bus)
    // offer.bus = freshOffer.bus;

    phoneCtrl.text = offer.phone ?? '';
    emailCtrl.text = offer.email ?? '';

    // ----------------------------------------
    // Ferry booking email (fires once on Confirmed)
    // ----------------------------------------
    if (statusBeforeSave != 'Confirmed' &&
        freshOffer.status == 'Confirmed') {
      // Use in-memory offer: ferryPerLeg is populated by _calcRound
      _maybeSendFerryEmail(offer);
    }

    freshOffer.status =
        _mapCalendarStatus(freshOffer.status);

    CurrentOfferStore.set(freshOffer);

    // ----------------------------------------
    // Sync back to state
    // ----------------------------------------
    offer.status = freshOffer.status;
    offer.pricingOverride = freshOffer.pricingOverride;
    CurrentOfferStore.set(offer);

    // ----------------------------------------
    // Sync calendar (PER ROUND BUS)
    // ----------------------------------------
    await CalendarSyncService.syncFromOffer(
  freshOffer,
  draftId: id,
  calcCache: _roundCalcCache,
);

    await _syncWaitingListAfterSave();

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
              ? "Lagret på ${fmtBus(firstBus)} ✅"
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
  } finally {
    _selfSaving = false;
  }
}

// ------------------------------------------------------------
// Ferry booking email — fires once when status → Confirmed
// ------------------------------------------------------------
void _maybeSendFerryEmail(OfferDraft confirmed) {
  // Collect all ferry legs across all rounds
  bool hasFerries = false;
  for (final r in confirmed.rounds) {
    if (r.ferryPerLeg.any((f) => f != null && f.isNotEmpty)) {
      hasFerries = true;
      break;
    }
  }

  debugPrint('FERRY EMAIL: hasFerries=$hasFerries, '
      'rounds=${confirmed.rounds.length}, '
      'ferryPerLeg=${confirmed.rounds.map((r) => r.ferryPerLeg).toList()}');

  if (!hasFerries) return;

  EmailService.sendFerryBookingEmail(offer: confirmed).then((_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ferry booking email sent ✅')),
    );
  }).catchError((e) {
    debugPrint('Ferry email error: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ferry email failed: $e'),
        backgroundColor: Colors.orange,
      ),
    );
  });
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
  // ✅ PRE-FETCH ALL LEGS IN PARALLEL
  // Fires all unique route lookups simultaneously so the sequential
  // merge loop below only hits the in-memory cache (near-instant).
  // ------------------------------------------------------------
  Future<void> _prefetchLegsParallel(
    List<RoundEntry> entries,
    String start,
  ) async {
    final queued = <String>{};
    final futures = <Future<void>>[];

    for (int i = 0; i < entries.length; i++) {
      final from   = _findPreviousRealLocation(entries, i, start);
      final toRaw  = _norm(entries[i].location);
      final toLower = toRaw.toLowerCase();

      if (toLower == 'off' || toLower == 'travel') continue;
      if (_norm(from).toLowerCase() == toLower) continue;

      final key = _cacheKey(_norm(from), toRaw);
      if (queued.contains(key)) continue;
      if (_distanceCache.containsKey(key)) continue;

      queued.add(key);
      futures.add(_fetchLegData(from: from, to: toRaw, index: i));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
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
    _noDDriveByIndex[index] = _noDDriveCache[key] ?? false;
    _kmSeNullByIndex[index] = _kmSeNullCache[key] ?? false;

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

    // toll_nightliner is no longer used — toll is computed as km * rate
    const double toll = 0.0;

    final extra =
        (res['extra'] as String?)?.trim() ?? '';

    final noDDrive = (res['no_ddrive'] as bool?) ?? false;

    // Track whether km_se was NULL (not yet computed by KmSeUpdater).
    // km_se = NULL  →  unknown (not computed yet)
    // km_se = 0     →  computed, confirmed non-Swedish route
    // km_se > 0     →  computed, X km are in Sweden
    final bool kmSeIsNull = res['km_se'] == null;

    // ===================================================
    // COUNTRY KM BREAKDOWN
    // ===================================================
    final Map<String, double> countryKm = {
      if ((res['km_se'] as num?) != null && (res['km_se'] as num) > 0)
        'SE': (res['km_se'] as num).toDouble(),
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
    _noDDriveCache[key]  = noDDrive;
    _kmSeNullCache[key]  = kmSeIsNull;

    // ===================================================
    // PER-INDEX WRITE (UI + CALC)
    // ===================================================
    _ferryByIndex[index]      = ferryPrice;
    _tollByIndex[index]       = toll;
    _extraByIndex[index]      = extra;
    _ferryNameByIndex[index] = ferryName;
    _countryKmByIndex[index] = countryKm;
    _kmSeNullByIndex[index]  = kmSeIsNull;

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
      _noDDriveByIndex = {};
      _travelBefore = [];
      _kmError = null;
    });

    // Fyll cache med tomme resultater slik at build() alltid har data
    await _recalcAllRounds();
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
  final Map<int, bool> noDDriveByIndex = {};
  final Map<int, bool> kmSeNullByIndex = {};

  final List<bool> travelBefore =
      List<bool>.filled(entries.length, false);

  bool missing = false;

  int? pendingTravelIndex;
  bool inTravelBlock = false;

  // ===================================================
  // PRE-FETCH — fire all route lookups in parallel so
  // the sequential merge loop below only hits the cache.
  // ===================================================
  await _prefetchLegsParallel(entries, start);

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
      kmSeNullByIndex[i] = false;

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
      kmSeNullByIndex[i] = false;

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
      kmSeNullByIndex[i] = false;

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
    final noDDrive = _noDDriveCache[key] ?? false;
    final kmSeNull = _kmSeNullCache[key] ?? false;

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
      noDDriveByIndex[pendingTravelIndex] = noDDrive;
      kmSeNullByIndex[pendingTravelIndex] = kmSeNull;

      // null ut dagens leg
      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      extraByIndex[i] = '';
      ferryNameByIndex[i] = '';
      countryKmByIndex[i] = {};
      noDDriveByIndex[i] = false;
      kmSeNullByIndex[i] = false;

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
    noDDriveByIndex[i] = noDDrive;
    kmSeNullByIndex[i] = kmSeNull;

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
    _noDDriveByIndex = noDDriveByIndex;
    _kmSeNullByIndex = kmSeNullByIndex;
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
    // Clear swe cache entry for empty rounds
    _sweCalcCache.remove(ri);

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

  // Pre-fetch any legs not already in cache (no-op if _recalcAllRounds
  // already pre-fetched everything).
  await _prefetchLegsParallel(entries, start);

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
      _countryKmByIndex[i] = {};
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
      _countryKmByIndex[i] = {};

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
      _countryKmByIndex[i] = {};
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

      // Move country km to the travel index (mirror _recalcKm behaviour)
      _countryKmByIndex[pendingTravelIndex] =
          Map<String, double>.from(_countryKmByIndex[i] ?? {});
      _kmSeNullByIndex[pendingTravelIndex] = _kmSeNullCache[key] ?? false;

      kmByIndex[i] = 0;
      ferryByIndex[i] = 0;
      tollByIndex[i] = 0;
      _countryKmByIndex[i] = {};
      _kmSeNullByIndex[i] = false;

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
    _kmSeNullByIndex[i] = _kmSeNullCache[key] ?? false;

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

final safeNoDDrive = List<bool>.generate(
  len,
  (i) => _noDDriveByIndex[i] ?? false,
);

  // Store ferry-per-leg on the round model so it can be used at save time
  offer.rounds[ri].ferryPerLeg = safeFerryPerLeg;

  // ================= SWEDISH MODEL =================

  // Swedish km are toll-free — subtract from the km base used for toll.
  //
  // If km_se is NULL (not yet computed by KmSeUpdater), we distinguish:
  //   - km_se = NULL  →  _kmSeNullByIndex[i] == true  → unknown, treat as Swedish
  //   - km_se = 0     →  _kmSeNullByIndex[i] == false → confirmed non-Swedish
  //   - km_se > 0     →  _kmSeNullByIndex[i] == false → confirmed partial/full Swedish
  final totalSweKm = List.generate(len, (i) {
    final seKm = _countryKmByIndex[i]?['SE'];
    if (seKm != null && seKm > 0) return seKm;           // km_se set and > 0
    if (_kmSeNullByIndex[i] == true) {
      // km_se not yet computed — conservatively treat entire leg as Swedish
      // (toll-free) to avoid incorrectly charging toll on Swedish routes.
      // Run the KmSeUpdater to populate correct values.
      return kmByIndex[i] ?? 0.0;
    }
    return 0.0;                                           // km_se = 0 confirmed
  }).fold<double>(0.0, (a, b) => a + b);
  final tollableKm = (totalKm - totalSweKm).clamp(0.0, double.infinity);

  debugPrint('🇸🇪 Round $ri: totalKm=${totalKm.toStringAsFixed(1)} sweKm=${totalSweKm.toStringAsFixed(1)} tollableKm=${tollableKm.toStringAsFixed(1)} (nullLegs=${List.generate(len, (i) => _kmSeNullByIndex[i] == true ? 1 : 0).fold(0, (a, b) => a + b)})');

  if (offer.pricingModel == 'svensk') {
    final swe = SettingsStore.current.sweSettings;

    // Determine international allowances per leg from country km data
    final utlTrkt = List<int>.generate(len, (i) {
      final cKm = _countryKmByIndex[i];
      if (cKm == null || cKm.isEmpty) return 0;
      final hasIntl = cKm.entries.any(
        (e) => e.key.toUpperCase() != 'SE' && e.value > 0,
      );
      return hasIntl ? 1 : 0;
    });

    // Pass entry dates so SweCalculator can deduplicate vehicle/driver
    // for legs that share the same date (e.g. last show + return home).
    final legDates = List<DateTime>.generate(
      len,
      (i) => i < entries.length ? entries[i].date : DateTime(2000),
    );

    final sweResult = SweCalculator.calculateRound(
      settings: swe,
      legKm: safeLegKm,
      dates: legDates,
      trailer: round.trailer,
      utlTraktPerLeg: utlTrkt,
      pickupEveningFirstDay: round.pickupEveningFirstDay,
    );

    final busCount = offer.rounds[ri].busSlots
            .whereType<String>()
            .where((x) => x.isNotEmpty)
            .length;
    final effectiveBusCount = busCount == 0 ? 1 : busCount;

    // Scale per-leg totals and round grand total up to nearest 1000 SEK
    final scaledLegTotal = sweResult.legTotal
        .map((v) => v * effectiveBusCount)
        .toList();
    final rawScaled = sweResult.totalCost * effectiveBusCount;
    final scaledTotal =
        (rawScaled / 1000).ceil() * 1000.0;

    final scaledSweResult = SweCalcResult(
      legKm: sweResult.legKm,
      legVehicleCost: sweResult.legVehicleCost,
      legKmCost: sweResult.legKmCost,
      legDriverCost: sweResult.legDriverCost,
      legDdCost: sweResult.legDdCost,
      legExtraCost: sweResult.legExtraCost,
      legTrailerCost: sweResult.legTrailerCost,
      legInternationalCost: sweResult.legInternationalCost,
      legTotal: scaledLegTotal,
      totalCost: scaledTotal,
      vehicleDagpris: sweResult.vehicleDagpris,
      chaufforDagpris: sweResult.chaufforDagpris,
      ddDagpris: sweResult.ddDagpris,
      milpris: sweResult.milpris,
    );
    _sweCalcCache[ri] = scaledSweResult;

    // Ferry: use FerryResolver (same as Norwegian) — consistent trailer pricing
    final roundFerryCost =
        FerryResolver.resolveTotalFerryCost(
          ferries: SettingsStore.current.ferries,
          trailer: round.trailer,
          ferryPerLeg: safeFerryPerLeg,
        ) * effectiveBusCount;

    // Toll: exclude Swedish km (toll-free in Sweden)
    final roundTollCost = tollableKm * SettingsStore.current.tollKmRate * effectiveBusCount;

    // Create minimal RoundCalcResult for UI compatibility (km stats etc.)
    final minimal = RoundCalcResult(
      billableDays: round.billableDays,
      includedKm: 0,
      extraKm: 0,
      dDriveDays: 0,
      flightTickets: 0,
      legKm: safeLegKm,
      tollPerLeg: safeToll,
      extraPerLeg: safeExtra,
      hasTravelBefore: safeTravel,
      noDDrivePerLeg: safeNoDDrive,
      dayCost: 0,
      extraKmCost: 0,
      dDriveCost: 0,
      trailerDayCost: 0,
      trailerKmCost: 0,
      ferryCost: roundFerryCost,
      tollCost: roundTollCost,
      flightCost: 0,
      totalCost: scaledTotal + roundFerryCost + roundTollCost,
    );
    _roundCalcCache[ri] = minimal;
    return minimal;
  }

  // ================= RESULT =================
  final result = TripCalculator.calculateRound(

    settings: _effectiveSettings(),
    dates: dates,
    pickupEveningFirstDay: round.pickupEveningFirstDay,
    trailer: round.trailer,
    totalKm: totalKm,
    tollableKm: tollableKm, // excludes Swedish km (toll-free)
    legKm: safeLegKm,
    ferries: SettingsStore.current.ferries,
    ferryPerLeg: safeFerryPerLeg, // 🔥 nå korrekt
    tollPerLeg: safeToll,
    extraPerLeg: safeExtra,
    hasTravelBefore: safeTravel,
    noDDrivePerLeg: safeNoDDrive,
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
  hasTravelBefore: result.hasTravelBefore,
  noDDrivePerLeg: result.noDDrivePerLeg,

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
  String _sek(double v) => "${v.toStringAsFixed(0)} SEK";

  // ===================================================
  // SWEDISH ROUND BREAKDOWN
  // ===================================================

  String _buildSweRoundBreakdown(int ri, SweCalcResult r) {
    final b = StringBuffer();
    b.writeln("SWEDISH ROUND CALCULATION");
    b.writeln("----------------------------");
    b.writeln("Vehicle/day:  ${_sek(r.vehicleDagpris)}");
    b.writeln("Driver/day:   ${_sek(r.chaufforDagpris)}");
    if (r.ddDagpris > 0) b.writeln("DD/day:       ${_sek(r.ddDagpris)}");
    b.writeln("Km price:     ${r.milpris.toStringAsFixed(0)} SEK/10km");
    b.writeln();

    final round = offer.rounds[ri];
    for (int i = 0; i < r.legKm.length; i++) {
      if (r.legKm[i] <= 0) continue;
      if (i >= round.entries.length) continue;

      final date = _fmtDate(round.entries[i].date);
      b.writeln("$date  (${r.legKm[i].toStringAsFixed(0)} km)");
      b.writeln("  Vehicle:       ${_sek(r.legVehicleCost[i])}");
      b.writeln("  Km cost:       ${_sek(r.legKmCost[i])}");
      b.writeln("  Driver:        ${_sek(r.legDriverCost[i])}");
      if (r.legDdCost[i] > 0)
        b.writeln("  DD:            ${_sek(r.legDdCost[i])}");
      if (r.legExtraCost[i] > 0)
        b.writeln("  Extra:         ${_sek(r.legExtraCost[i])}");
      if (r.legTrailerCost[i] > 0)
        b.writeln("  Trailer:       ${_sek(r.legTrailerCost[i])}");
      if (r.legInternationalCost[i] > 0)
        b.writeln("  International: ${_sek(r.legInternationalCost[i])}");
      b.writeln("  Leg total: ${_sek(r.legTotal[i])}");
      b.writeln();
    }

    b.writeln("----------------------------");
    b.writeln("TOTAL: ${_sek(r.totalCost)}");
    return b.toString();
  }

  // ===================================================
  // SWEDISH TOTAL BREAKDOWN (all rounds)
  // ===================================================

  String _buildSweTotalBreakdown() {
    final usedEntries = _sweCalcCache.entries
        .where((e) => offer.rounds[e.key].entries.isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (usedEntries.isEmpty) return "No rounds calculated yet.";

    final b = StringBuffer();
    double grandTotal = 0;

    for (final entry in usedEntries) {
      final ri = entry.key;
      final r = entry.value;
      final round = offer.rounds[ri];

      final buses = round.busSlots
          .whereType<String>()
          .where((x) => x.isNotEmpty)
          .map(fmtBus)
          .join(', ');
      final busLabel = buses.isNotEmpty ? buses : 'No bus';

      final norR = _roundCalcCache[ri];
      final ferry = norR?.ferryCost ?? 0.0;
      final toll = norR?.tollCost ?? 0.0;

      b.writeln("ROUND ${ri + 1}  ($busLabel)");
      b.writeln("----------------------------");
      b.writeln("  Vehicle/day: ${_sek(r.vehicleDagpris)}");
      b.writeln("  Km price:    ${r.milpris.toStringAsFixed(0)} SEK/10km");

      for (int i = 0; i < r.legKm.length; i++) {
        if (r.legKm[i] > 0) {
          final date = i < round.entries.length
              ? _fmtDate(round.entries[i].date)
              : "Leg ${i + 1}";
          b.writeln(
            "  $date: ${r.legKm[i].toStringAsFixed(0)} km"
            " → ${_sek(r.legTotal[i])}",
          );
        }
      }

      b.writeln("  Swedish subtotal: ${_sek(r.totalCost)}");
      if (ferry > 0) b.writeln("  Ferry:           ${_sek(ferry)}");
      if (toll > 0) b.writeln("  Toll:            ${_sek(toll)}");
      final roundTotal = r.totalCost + ferry + toll;
      b.writeln("  Round total: ${_sek(roundTotal)}");
      b.writeln();
      grandTotal += roundTotal;
    }

    b.writeln("============================");
    b.writeln("GRAND TOTAL: ${_sek(grandTotal)}");
    return b.toString();
  }

// ------------------------------------------------------------
// ✅ Open Create Invoice Dialog
// ------------------------------------------------------------
Future<void> _openCreateInvoiceDialog() async {
  // 1. Generate auto invoice number
  String invoiceNumber;
  try {
    invoiceNumber = await InvoiceService.generateInvoiceNumber();
  } catch (e) {
    invoiceNumber = "${DateTime.now().year}-001";
  }

  // 2. Defaults
  final now = DateTime.now();
  DateTime invoiceDate = now;
  DateTime dueDate = now.add(const Duration(days: 14));

  final invoiceNumberCtrl =
      TextEditingController(text: invoiceNumber);
  final bankAccountCtrl = TextEditingController(
      text: SettingsStore.current.bankAccount);
  final paymentRefCtrl = TextEditingController(
      text: invoiceNumber.replaceAll('-', ''));

  if (!mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text("Create invoice"),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice number
                    TextField(
                      controller: invoiceNumberCtrl,
                      decoration: const InputDecoration(
                        labelText: "Invoice number",
                        hintText: "2025-001",
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Invoice date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Invoice date"),
                      subtitle: Text(
                        DateFormat("dd.MM.yyyy").format(invoiceDate),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: invoiceDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2099),
                        );
                        if (picked != null) {
                          setLocal(() => invoiceDate = picked);
                        }
                      },
                    ),

                    // Due date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Due date"),
                      subtitle: Text(
                        DateFormat("dd.MM.yyyy").format(dueDate),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: dueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2099),
                        );
                        if (picked != null) {
                          setLocal(() => dueDate = picked);
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    // Bank account
                    TextField(
                      controller: bankAccountCtrl,
                      decoration: const InputDecoration(
                        labelText: "Bank account",
                        hintText: "9710.05.12345",
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Payment reference
                    TextField(
                      controller: paymentRefCtrl,
                      decoration: const InputDecoration(
                        labelText: "Reference",
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Create"),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return;

  // 3. Calculate totals
  // Ensure all rounds are calculated
  for (int i = 0; i < offer.rounds.length; i++) {
    if (!_roundCalcCache.containsKey(i)) {
      _roundCalcCache[i] = await _calcRound(i);
    }
  }

  double grandTotal = 0;
  for (final res in _roundCalcCache.values) {
    grandTotal += res.totalCost;
  }

  final countryKm = _collectAllCountryKm();
  final vatBreakdown = _calculateForeignVat(
    basePrice: grandTotal,
    countryKm: countryKm,
  );
  final totalInclVat =
      grandTotal + vatBreakdown.values.fold(0.0, (a, b) => a + b);

  try {
    // 4. Save to Supabase
    final invoice = await InvoiceService.createFromOffer(
      offer: offer,
      roundCalc: _roundCalcCache,
      invoiceNumber: invoiceNumberCtrl.text.trim(),
      invoiceDate: invoiceDate,
      dueDate: dueDate,
      bankAccount: bankAccountCtrl.text.trim(),
      paymentRef: paymentRefCtrl.text.trim(),
      totalExclVat: grandTotal,
      vatBreakdown: vatBreakdown,
      totalInclVat: totalInclVat,
      countryKm: countryKm,
      offerId: _draftId,
    );

    // 5. Generate and download PDF
    final bytes = await InvoicePdfService.generatePdf(invoice);
    final safe = _safeFolderName(
      offer.production.trim().isEmpty ? "invoice" : offer.production.trim(),
    );
    await savePdf(bytes, "Faktura ${invoice.invoiceNumber} $safe.pdf");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Faktura ${invoice.invoiceNumber} opprettet og lagret",
        ),
      ),
    );
  } catch (e, st) {
    debugPrint("INVOICE CREATE ERROR: $e\n$st");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Feil ved opprettelse av faktura: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}

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

final calc = _roundCalcCache[roundIndex];

if (calc == null) {
  return const Center(child: CircularProgressIndicator());
}
// =====================================================
// ALL ROUNDS TOTAL (RIGHT CARD / VAT / TOTAL)
// =====================================================

double allRoundsTotal = 0;
double allRoundsFerry = 0;
double allRoundsToll = 0;

if (offer.pricingModel == 'svensk') {
  for (int i = 0; i < offer.rounds.length; i++) {
    final sweR = _sweCalcCache[i];
    final norR = _roundCalcCache[i];
    if (sweR != null && offer.rounds[i].entries.isNotEmpty) {
      allRoundsTotal += sweR.totalCost; // Swedish base (SEK)
      if (norR != null) {
        allRoundsTotal += norR.ferryCost + norR.tollCost;
        allRoundsFerry += norR.ferryCost;
        allRoundsToll += norR.tollCost;
      }
    }
  }
} else {
  for (int i = 0; i < offer.rounds.length; i++) {
    final r = _roundCalcCache[i];
    if (r != null) {
      allRoundsTotal += r.totalCost;
      allRoundsFerry += r.ferryCost;
      allRoundsToll += r.tollCost;
    }
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

// allRoundsTotal is the gross (VAT-inclusive) price.
// VAT is extracted from it (not added on top).
// "incl VAT" = the gross price; "excl VAT" = gross − extracted VAT.
final _vatTotalForDisplay =
    foreignVatMap.values.fold(0.0, (a, b) => a + b);
final totalIncVat = allRoundsTotal;                        // gross price
final totalExVat  = allRoundsTotal - _vatTotalForDisplay;  // net of foreign VAT


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
          onCreateInvoice: _openCreateInvoiceDialog,
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
    i < offer.rounds[roundIndex].busSlots.length
        ? offer.rounds[roundIndex].busSlots[i]
        : null;

final trailer =
    i < offer.rounds[roundIndex].trailerSlots.length
        ? offer.rounds[roundIndex].trailerSlots[i]
        : false;

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

                Icon(
                  bus == "WAITING_LIST"
                      ? Icons.hourglass_top_outlined
                      : Icons.directions_bus,
                  size: 20,
                  color: bus == "WAITING_LIST"
                      ? Colors.orange.shade600
                      : null,
                ),
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
              (b) => b != null && b != "WAITING_LIST",
              orElse: () => null,
            );
  });

  CurrentOfferStore.set(offer);

  await _recalcAllRounds(); // ⭐ DENNE
},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        bus == "WAITING_LIST"
                            ? "Waiting list"
                            : (bus != null ? fmtBus(bus) : "Select bus"),
                        style: TextStyle(
                          color: bus == "WAITING_LIST"
                              ? Colors.orange.shade700
                              : (bus == null ? Colors.grey : Colors.black),
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

                // ---------- EXTRA text (D.Drive / Ferry / Bridge)
                final bool travelBefore = _hasTravelBefore(round.entries, i);
                final bool isTravel = toLower == 'travel';
                final bool hasDDrive = km != null &&
                    (_noDDriveByIndex[i] != true) &&
                    (travelBefore ? km >= 1200 : km >= 600);

                // Ferry/Bridge: show on Travel row, suppress on city row after Travel.
                String rawExtra;
                if (isTravel) {
                  // For Travel row: try own extra first, else look ahead to next real city.
                  rawExtra = _extraByIndex[i] ?? '';
                  if (rawExtra.isEmpty) {
                    for (int j = i + 1; j < round.entries.length; j++) {
                      final jLoc =
                          _norm(round.entries[j].location).toLowerCase();
                      if (jLoc.isEmpty || jLoc == 'travel') continue;
                      if (jLoc != 'off') rawExtra = _extraByIndex[j] ?? '';
                      break;
                    }
                  }
                } else if (travelBefore) {
                  rawExtra = ''; // Ferry/Bridge already shown on Travel row above.
                } else {
                  rawExtra = _extraByIndex[i] ?? '';
                }

                final extraParts = <String>[];
                if (hasDDrive) extraParts.add('D.Drive');
                for (final p in rawExtra
                    .split(RegExp(r'[,/]'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)) {
                  if (p.toLowerCase().contains('ferry')) extraParts.add('Ferry');
                  if (p.toLowerCase().contains('bridge')) extraParts.add('Bridge');
                }
                final String extraText = extraParts.join(' / ');

                return _RoutesTableRow(
                  date: _fmtDate(e.date),
                  route: routeText,
                  km: km,
                  extra: extraText,
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
            width: 360,
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
      onDeleteRound: _deleteRound,
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
    value: "Invoiced",
    child: Text("🧾 Invoiced"),
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

      // ================= PRICING MODEL TOGGLE =================
      const Text(
        "Pricing model",
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'norsk', label: Text("🇳🇴 Norwegian")),
          ButtonSegment(value: 'svensk', label: Text("🇸🇪 Swedish")),
        ],
        selected: {offer.pricingModel},
        onSelectionChanged: (selected) async {
          setState(() {
            offer.pricingModel = selected.first;
            _sweCalcCache.clear();
            _roundCalcCache.clear();
          });
          await _recalcAllRounds();
        },
      ),

      const SizedBox(height: 12),

Container(
  decoration: BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.outlineVariant),
  ),
  child: Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: false,
      onExpansionChanged: (v) => setState(() => _calcExpanded = v),
      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      title: Text(
        "Round calculation",
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            offer.pricingModel == 'svensk'
                ? (_sweCalcCache[roundIndex] != null
                    ? _buildSweRoundBreakdown(
                        roundIndex, _sweCalcCache[roundIndex]!)
                    : "Calculating...")
                : _buildRoundBreakdown(
                    roundIndex, calc, _effectiveSettings()),
            style: const TextStyle(
              fontFamily: "monospace",
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  ),
),

      // ---------- TOTAL CALCULATION ----------
      const SizedBox(height: 10),

Container(
  decoration: BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.outlineVariant),
  ),
  child: Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: false,
      onExpansionChanged: (v) => setState(() => _totalExpanded = v),
      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      title: Text(
        "Total calculation",
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            offer.pricingModel == 'svensk'
                ? _buildSweTotalBreakdown()
                : _buildTotalBreakdown(_effectiveSettings()),
            style: const TextStyle(
              fontFamily: "monospace",
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  ),
),

      ...[
        const SizedBox(height: 10),

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
                fmt: offer.pricingModel == 'svensk' ? _sek : _nok,
              ),
            ],
          ),
        ),
      ],
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
  final Future<void> Function() onCreateInvoice;
  final String? draftId;

  const _LeftOfferCard({
  super.key,
  required this.offer,
  required this.onExport,
  required this.onSave,
  required this.onScanPdf,
  required this.onCreateInvoice,
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
_PricingOverrideCard(
  offer: widget.offer,
  onChanged: () {

    setState(() {});

    // 🔥 Recalc totals live
    final state =
        context.findAncestorStateOfType<_NewOfferPageState>();

    state?._recalcAllRounds();
    CurrentOfferStore.set(widget.offer);
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

    const SizedBox(height: 8),

    // -------- OPPRETT FAKTURA --------
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: widget.onCreateInvoice,
        icon: const Icon(Icons.receipt_long),
        label: const Text("Create invoice"),
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
// ------------------------------------------------------------
// PRICING OVERRIDE CARD (DRAFT LEVEL)
// ------------------------------------------------------------
class _PricingOverrideCard extends StatefulWidget {
  final OfferDraft offer;
  final VoidCallback onChanged;

  const _PricingOverrideCard({
    required this.offer,
    required this.onChanged,
  });

  @override
  State<_PricingOverrideCard> createState() =>
      _PricingOverrideCardState();
}

class _PricingOverrideCardState extends State<_PricingOverrideCard> {

  late final TextEditingController _dayCtrl;
  late final TextEditingController _extraKmCtrl;
  late final TextEditingController _trailerDayCtrl;
  late final TextEditingController _trailerKmCtrl;
  late final TextEditingController _dDriveCtrl;
  late final TextEditingController _flightCtrl;

  late bool _localEnabled;

  // --------------------------------------------------
  // CURRENT VALUES
  // --------------------------------------------------
  OfferPricingOverride _current() {
    final global = SettingsStore.current;

    return widget.offer.pricingOverride ??
        OfferPricingOverride(
          dayPrice: global.dayPrice,
          extraKmPrice: global.extraKmPrice,
          trailerDayPrice: global.trailerDayPrice,
          trailerKmPrice: global.trailerKmPrice,
          dDriveDayPrice: global.dDriveDayPrice,
          flightTicketPrice: global.flightTicketPrice,
        );
  }

  // --------------------------------------------------
  // INIT
  // --------------------------------------------------
  @override
  void initState() {
    super.initState();

    _localEnabled = widget.offer.pricingOverride != null;

    final p = _current();

    _dayCtrl = TextEditingController(text: p.dayPrice.toStringAsFixed(0));
    _extraKmCtrl = TextEditingController(text: p.extraKmPrice.toStringAsFixed(0));
    _trailerDayCtrl = TextEditingController(text: p.trailerDayPrice.toStringAsFixed(0));
    _trailerKmCtrl = TextEditingController(text: p.trailerKmPrice.toStringAsFixed(0));
    _dDriveCtrl = TextEditingController(text: p.dDriveDayPrice.toStringAsFixed(0));
    _flightCtrl = TextEditingController(text: p.flightTicketPrice.toStringAsFixed(0));
  }

  // --------------------------------------------------
  // 🔥 VIKTIGSTE FIXEN – Sync når draft reloades
  // --------------------------------------------------
  @override
  void didUpdateWidget(covariant _PricingOverrideCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.offer.pricingOverride != widget.offer.pricingOverride) {

      _localEnabled = widget.offer.pricingOverride != null;

      final p = _current();

      _dayCtrl.text = p.dayPrice.toStringAsFixed(0);
      _extraKmCtrl.text = p.extraKmPrice.toStringAsFixed(0);
      _trailerDayCtrl.text = p.trailerDayPrice.toStringAsFixed(0);
      _trailerKmCtrl.text = p.trailerKmPrice.toStringAsFixed(0);
      _dDriveCtrl.text = p.dDriveDayPrice.toStringAsFixed(0);
      _flightCtrl.text = p.flightTicketPrice.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _extraKmCtrl.dispose();
    _trailerDayCtrl.dispose();
    _trailerKmCtrl.dispose();
    _dDriveCtrl.dispose();
    _flightCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // UPDATE MODEL
  // --------------------------------------------------
  void _update(OfferPricingOverride v) {
  widget.offer.pricingOverride = v;
  CurrentOfferStore.set(widget.offer); // 🔥 MANGLET
  widget.onChanged();
}

  // --------------------------------------------------
  // FIELD
  // --------------------------------------------------
  Widget _field(
    String label,
    TextEditingController ctrl,
    void Function(double) onChanged,
  ) {
    return TextField(
      controller: ctrl,
      enabled: _localEnabled,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        final d = double.tryParse(v.replaceAll(',', '.'));
        if (d != null) onChanged(d);
      },
    );
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _current();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            "Pricing (per draft)",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Override global pricing"),
              value: _localEnabled,
              onChanged: (v) {
                setState(() {
                  _localEnabled = v;
                  widget.offer.pricingOverride = v ? _current() : null;
                });
                CurrentOfferStore.set(widget.offer);
                widget.onChanged();
              },
            ),

            const SizedBox(height: 6),

            _field("Day price",      _dayCtrl,       (d) => _update(p.copyWith(dayPrice: d))),
            _field("Extra km price", _extraKmCtrl,   (d) => _update(p.copyWith(extraKmPrice: d))),
            _field("Trailer day",    _trailerDayCtrl,(d) => _update(p.copyWith(trailerDayPrice: d))),
            _field("Trailer km",     _trailerKmCtrl, (d) => _update(p.copyWith(trailerKmPrice: d))),
            _field("D.Drive",        _dDriveCtrl,    (d) => _update(p.copyWith(dDriveDayPrice: d))),
            _field("Flight ticket",  _flightCtrl,    (d) => _update(p.copyWith(flightTicketPrice: d))),
          ],
        ),
      ),
    );
  }
}
class _RoutesTableHeader extends StatelessWidget {
  const _RoutesTableHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = (constraints.maxWidth / 620).clamp(0.45, 1.0);
      final headerStyle = TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: (14 * s).clamp(9.0, 14.0),
      );
      return Row(
        children: [
          SizedBox(width: 105 * s, child: Text("Date",  style: headerStyle)),
          SizedBox(width: 10 * s),
          SizedBox(width: 180 * s, child: Text("Route", style: headerStyle)),
          SizedBox(width: 10 * s),
          SizedBox(width: 52 * s,  child: Text("KM",    style: headerStyle)),
          SizedBox(width: 10 * s),
          Expanded(child: Text("Extra", style: headerStyle)),
          const SizedBox(width: 56),
        ],
      );
    });
  }
}
class _RoutesTableRow extends StatelessWidget {
  final String date;
  final String route;
  final double? km;
  final String extra;
  final Map<String, double> countryKm;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutesTableRow({
    required this.date,
    required this.route,
    required this.km,
    required this.extra,
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

    return LayoutBuilder(builder: (context, constraints) {
      final s = (constraints.maxWidth / 620).clamp(0.45, 1.0);
      final vPad = (8 * s).clamp(4.0, 8.0);

      return Padding(
        padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 6),
        child: Row(
          children: [

            // DATE
            SizedBox(
              width: 105 * s,
              child: Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: (14 * s).clamp(9.0, 14.0),
                ),
              ),
            ),

            SizedBox(width: 10 * s),

            // ROUTE
            SizedBox(
              width: 180 * s,
              child: Text(
                route,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: (14 * s).clamp(9.0, 14.0),
                ),
              ),
            ),

            SizedBox(width: 10 * s),

            // KM
            Tooltip(
              message: tooltipText.isEmpty ? "No country breakdown" : tooltipText,
              child: SizedBox(
                width: 52 * s,
                child: Text(
                  km == null ? "?" : km!.toStringAsFixed(0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: (14 * s).clamp(9.0, 14.0),
                    color: km == null ? cs.error : cs.onSurface,
                  ),
                ),
              ),
            ),

            SizedBox(width: 10 * s),

            // EXTRA — fills all remaining space so long strings aren't cut
            Expanded(
              child: Text(
                extra,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (13 * s).clamp(8.0, 13.0),
                  color: extra.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
            ),

            // BUTTONS
            SizedBox(
              width: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
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
            onChanged: (v) async {
  if (v == null) return;

  offer.busCount = v;

  for (final r in offer.rounds) {

    // =========================
    // 🔥 EXPAND when increasing buses
    // =========================
    while (r.busSlots.length < v) {
      r.busSlots.add(null);
    }

    while (r.trailerSlots.length < v) {
      r.trailerSlots.add(false);
    }

    // =========================
    // 🔥 TRIM when decreasing buses
    // =========================
    if (r.busSlots.length > v) {
      r.busSlots = r.busSlots.take(v).toList();
    }

    if (r.trailerSlots.length > v) {
      r.trailerSlots = r.trailerSlots.take(v).toList();
    }
  }

  // Expand / trim globalBusSlots to match new busCount
  while (offer.globalBusSlots.length < v) offer.globalBusSlots.add(null);
  if (offer.globalBusSlots.length > v) {
    offer.globalBusSlots = offer.globalBusSlots.take(v).toList();
  }

  onChanged();

  final state =
      context.findAncestorStateOfType<_NewOfferPageState>();

  if (state != null) {
    await state._recalcAllRounds();
    CurrentOfferStore.set(offer);
  }
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

          const Divider(height: 24),

          const Text(
            "Global allocation",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 8),

          ...List.generate(offer.busCount, (i) {
            final globalBus = i < offer.globalBusSlots.length
                ? offer.globalBusSlots[i]
                : null;

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final state =
                    context.findAncestorStateOfType<_NewOfferPageState>();
                if (state == null) return;

                final picked = await state._pickBusGlobal(i);
                if (picked == null) return;

                final oldGlobal = i < offer.globalBusSlots.length
                    ? offer.globalBusSlots[i]
                    : null;

                while (offer.globalBusSlots.length <= i) {
                  offer.globalBusSlots.add(null);
                }
                offer.globalBusSlots[i] = picked;

                // Propagate to rounds — preserve per-round overrides
                for (final r in offer.rounds) {
                  while (r.busSlots.length <= i) r.busSlots.add(null);
                  final cur = r.busSlots[i];
                  if (cur == null || cur == oldGlobal) {
                    r.busSlots[i] = picked;
                    r.bus = r.busSlots.firstWhere(
                      (b) => b != null && b != 'WAITING_LIST',
                      orElse: () => null,
                    );
                  }
                }

                if (!state.mounted) return;
                await state._recalcAllRounds();
                if (!state.mounted) return;
                CurrentOfferStore.set(offer);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      size: 18,
                      color: globalBus == null ? Colors.grey : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Bus ${i + 1}:",
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        globalBus != null ? fmtBus(globalBus) : "Not set",
                        style: TextStyle(
                          color: globalBus == null ? Colors.grey : null,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}