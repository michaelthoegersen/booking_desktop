import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../models/offer_draft.dart';
import '../services/trip_calculator.dart';
import '../services/offer_pdf_service.dart';
import '../state/settings_store.dart';
import '../widgets/offer_preview.dart';
import '../services/offer_storage_service.dart';

class NewOfferPage extends StatefulWidget {
  /// ✅ Hvis du sender inn offerId -> åpner den eksisterende draft
  final String? offerId;

  const NewOfferPage({super.key, this.offerId});

  @override
  State<NewOfferPage> createState() => _NewOfferPageState();
}

class _NewOfferPageState extends State<NewOfferPage> {
  int roundIndex = 0;

  // ✅ default values, men dette overskrives av loadDraft()
  final OfferDraft offer = OfferDraft(
    company: 'Norsk Turnétransport AS',
    contact: 'Michael',
    production: 'Karpe',
  );

  final TextEditingController companyCtrl = TextEditingController();
  final TextEditingController contactCtrl = TextEditingController();
  final TextEditingController productionCtrl = TextEditingController();

  final TextEditingController startLocCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();

  DateTime? selectedDate;

  // ✅ Offer/draft id in Supabase
  String? _draftId;

  bool _loadingDraft = false;

  final List<String> knownLocations = const [
    "Oslo",
    "Bergen",
    "Trondheim",
    "Stavanger",
    "Kristiansand",
    "Tromsø",
    "Lillestrøm",
    "Drammen",
    "Skien",
    "Sandefjord",
    "Ålesund",
    "Bodø",
    "Hamar",
    "Fredrikstad",
    "Berlin",
    "Wehnrath",
  ];

  SupabaseClient get sb => Supabase.instance.client;

  // ------------------------------------------------------------
  // caches per leg (from,to)
  // ------------------------------------------------------------
  final Map<String, double?> _distanceCache = {};
  final Map<String, double> _ferryCache = {};
  final Map<String, double> _tollCache = {};
  final Map<String, String> _extraCache = {};

  bool _loadingKm = false;
  String? _kmError;

  // per entry index (current round)
  Map<int, double?> _kmByIndex = {};
  Map<int, double> _ferryByIndex = {};
  Map<int, double> _tollByIndex = {};
  Map<int, String> _extraByIndex = {};

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    // init controllers from initial offer
    companyCtrl.text = offer.company;
    contactCtrl.text = offer.contact;
    productionCtrl.text = offer.production;

    _syncRoundControllers();

    // ✅ Hvis vi kom med offerId -> load draft først
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
    if ((newId == null || newId.isEmpty) && (oldId != null && oldId.isNotEmpty)) {
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
        offer.rounds[i].pickupEveningFirstDay = loaded.rounds[i].pickupEveningFirstDay;

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
  // Small helpers
  // ------------------------------------------------------------
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
      // keep start location of current round
      offer.rounds[roundIndex].startLocation = _norm(startLocCtrl.text);

      final id = await OfferStorageService.saveDraft(
        id: _draftId,
        offer: offer,
      );

      _draftId = id;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Draft saved ✅ (${_draftId!})")),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Draft save failed: $e")),
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

    // cache hit
    if (_distanceCache.containsKey(key)) {
      _ferryByIndex[index] = _ferryCache[key] ?? 0.0;
      _tollByIndex[index] = _tollCache[key] ?? 0.0;
      _extraByIndex[index] = _extraCache[key] ?? '';
      return _distanceCache[key];
    }

    Future<Map<String, dynamic>?> _queryExact(String a, String b) async {
      return await sb
          .from('routes_all')
          .select('distance_total_km, ferry_price, toll_nightliner, extra')
          .eq('from_place', a)
          .eq('to_place', b)
          .limit(1)
          .maybeSingle();
    }

    Future<Map<String, dynamic>?> _queryLike(String a, String b) async {
      return await sb
          .from('routes_all')
          .select('distance_total_km, ferry_price, toll_nightliner, extra')
          .ilike('from_place', '%$a%')
          .ilike('to_place', '%$b%')
          .limit(1)
          .maybeSingle();
    }

    try {
      Map<String, dynamic>? res = await _queryExact(fromN, toN);
      res ??= await _queryLike(fromN, toN);
      res ??= await _queryExact(toN, fromN);

      if (res == null) {
        _distanceCache[key] = null;
        _ferryCache[key] = 0.0;
        _tollCache[key] = 0.0;
        _extraCache[key] = '';
        _ferryByIndex[index] = 0.0;
        _tollByIndex[index] = 0.0;
        _extraByIndex[index] = '';
        return null;
      }

      final km = (res['distance_total_km'] as num?)?.toDouble();
      final ferry = (res['ferry_price'] as num?)?.toDouble() ?? 0.0;
      final toll = (res['toll_nightliner'] as num?)?.toDouble() ?? 0.0;
      final extra = (res['extra'] as String?)?.trim() ?? '';

      _distanceCache[key] = km;
      _ferryCache[key] = ferry;
      _tollCache[key] = toll;
      _extraCache[key] = extra;

      _ferryByIndex[index] = ferry;
      _tollByIndex[index] = toll;
      _extraByIndex[index] = extra;

      return km;
    } catch (_) {
      _distanceCache[key] = null;
      _ferryCache[key] = 0.0;
      _tollCache[key] = 0.0;
      _extraCache[key] = '';
      _ferryByIndex[index] = 0.0;
      _tollByIndex[index] = 0.0;
      _extraByIndex[index] = '';
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

    setState(() {
      offer.rounds[roundIndex].entries.add(
        RoundEntry(date: selectedDate!, location: loc, extra: ''),
      );
      offer.rounds[roundIndex].entries.sort((a, b) => a.date.compareTo(b.date));
      locationCtrl.clear();
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
        offer.rounds[roundIndex].entries.add(
          RoundEntry(date: selectedDate!, location: loc, extra: ''),
        );
      }
      offer.rounds[roundIndex].entries.sort((a, b) => a.date.compareTo(b.date));
      locationCtrl.clear();
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
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
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
    final entryCount = round.entries.length;

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

    final totalKm = kmByIndex.values.whereType<double>().fold<double>(0, (a, b) => a + b);
    final legKm = List.generate(entryCount, (i) => (kmByIndex[i] ?? 0.0).toDouble());

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
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF saved:\n$filePath")),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF export failed: $e")),
      );
    }
  }

  // ------------------------------------------------------------
  // ✅ Save PDF (FilePicker)
  // ------------------------------------------------------------
  Future<String> _savePdfToFile(Uint8List bytes) async {
    final production = offer.production.trim().isEmpty ? "UnknownProduction" : offer.production.trim();
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
    final entryCount = round.entries.length;

    final totalKm = _kmByIndex.values.whereType<double>().fold<double>(0, (a, b) => a + b);

    final ferryTotal = _ferryByIndex.values.fold<double>(0.0, (a, b) => a + b);
    final tollTotal = _tollByIndex.values.fold<double>(0.0, (a, b) => a + b);

    final calc = TripCalculator.calculateRound(
      settings: SettingsStore.current,
      entryCount: entryCount,
      pickupEveningFirstDay: round.pickupEveningFirstDay,
      trailer: round.trailer,
      totalKm: totalKm,
      legKm: List.generate(entryCount, (i) => (_kmByIndex[i] ?? 0.0).toDouble()),
      ferryCost: ferryTotal,
      tollCost: tollTotal,
    );

    if (_loadingDraft) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT
          SizedBox(
            width: 300,
            child: _LeftOfferCard(
              companyCtrl: companyCtrl,
              contactCtrl: contactCtrl,
              productionCtrl: productionCtrl,
              offer: offer,
              onChanged: () {
                setState(() {
                  offer.company = companyCtrl.text.trim();
                  offer.contact = contactCtrl.text.trim();
                  offer.production = productionCtrl.text.trim();
                });
              },
              onExport: _exportPdf,
              onSave: _saveDraft,
              draftId: _draftId,
            ),
          ),

          const SizedBox(width: 14),

          // CENTER
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
                  Row(
                    children: [
                      Text(
                        "Rounds",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<int>(
                          value: roundIndex,
                          decoration: const InputDecoration(labelText: "Round", prefixIcon: Icon(Icons.repeat)),
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(value: i, child: Text("Round ${i + 1}")),
                          ),
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() {
                              offer.rounds[roundIndex].startLocation = _norm(startLocCtrl.text);
                              roundIndex = v;
                              _syncRoundControllers();
                            });
                            await _recalcKm();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: startLocCtrl,
                    onChanged: (_) async {
                      setState(() => offer.rounds[roundIndex].startLocation = _norm(startLocCtrl.text));
                      await _recalcKm();
                    },
                    decoration: const InputDecoration(
                      labelText: "Start location (for this round)",
                      prefixIcon: Icon(Icons.flag),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: round.pickupEveningFirstDay,
                            onChanged: (v) => setState(() => round.pickupEveningFirstDay = v ?? false),
                          ),
                          const Text("Pickup evening (first day not billable)"),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: round.trailer,
                            onChanged: (v) => setState(() => round.trailer = v ?? false),
                          ),
                          const Text("Trailer"),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

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
                                  child: Text(selectedDate == null ? "Pick date" : _fmtDate(selectedDate!)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 140,
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: _loadingKm ? null : _addEntry,
                                icon: _loadingKm
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.add),
                                label: const Text("Add"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 56,
                          child: _LocationAutoComplete(
                            controller: locationCtrl,
                            suggestions: knownLocations,
                            onSubmit: _addEntry,
                            onPasteMulti: _pasteManyLines,
                          ),
                        ),
                        if (_kmError != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _kmError!,
                              style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

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
                          const _RoutesTableHeader(),
                          Divider(height: 14, color: cs.outlineVariant),
                          if (round.entries.isEmpty)
                            const Expanded(child: Center(child: Text("No entries yet.")))
                          else
                            Expanded(
                              child: ListView.separated(
                                itemCount: round.entries.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                                itemBuilder: (_, i) {
                                  final e = round.entries[i];
                                  final km = _kmByIndex[i];
                                  final from = i == 0 ? round.startLocation : round.entries[i - 1].location;
                                  final routeText = "${_norm(from)} → ${_norm(e.location)}";

                                  return _RoutesTableRow(
                                    date: _fmtDate(e.date),
                                    route: routeText,
                                    km: km,
                                    onEdit: () => _editEntry(i),
                                    onDelete: () async {
                                      setState(() => offer.rounds[roundIndex].entries.removeAt(i));
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
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                              Text("Included: ${calc.includedKm.toStringAsFixed(0)} km",
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              Text("Extra: ${calc.extraKm.toStringAsFixed(0)} km",
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              Text("Total: ${totalKm.toStringAsFixed(0)} km",
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                              color: cs.surfaceContainerLowest,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 6,
                                  children: [
                                    Text("Days: ${_nok(calc.dayCost)}", style: const TextStyle(fontWeight: FontWeight.w900)),
                                    Text("Extra km: ${_nok(calc.extraKmCost)}",
                                        style: const TextStyle(fontWeight: FontWeight.w900)),
                                    if (round.trailer)
                                      Text("Trailer: ${_nok(calc.trailerDayCost + calc.trailerKmCost)}",
                                          style: const TextStyle(fontWeight: FontWeight.w900)),
                                    if (ferryTotal > 0)
                                      Text("Ferry: ${_nok(calc.ferryCost)}", style: const TextStyle(fontWeight: FontWeight.w900)),
                                    if (tollTotal > 0)
                                      Text("Toll: ${_nok(calc.tollCost)}", style: const TextStyle(fontWeight: FontWeight.w900)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("TOTAL: ${_nok(calc.totalCost)}",
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
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

          SizedBox(
            width: 430,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: SingleChildScrollView(child: OfferPreview(offer: offer)),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// LEFT CARD
// ------------------------------------------------------------
class _LeftOfferCard extends StatelessWidget {
  final TextEditingController companyCtrl;
  final TextEditingController contactCtrl;
  final TextEditingController productionCtrl;
  final VoidCallback onChanged;

  final OfferDraft offer;
  final Future<void> Function() onExport;
  final Future<void> Function() onSave;

  final String? draftId;

  const _LeftOfferCard({
    required this.companyCtrl,
    required this.contactCtrl,
    required this.productionCtrl,
    required this.onChanged,
    required this.offer,
    required this.onExport,
    required this.onSave,
    required this.draftId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draftId == null ? "New Offer" : "Edit Offer",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            draftId == null ? "Not saved yet" : "ID: $draftId",
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 14),

          Text("Customer", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),

          TextField(
            controller: companyCtrl,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(labelText: "Company", prefixIcon: Icon(Icons.apartment_rounded)),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: contactCtrl,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(labelText: "Contact person", prefixIcon: Icon(Icons.person)),
          ),

          const SizedBox(height: 14),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 14),

          Text("Production", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),

          TextField(
            controller: productionCtrl,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(labelText: "Production / Band", prefixIcon: Icon(Icons.music_note)),
          ),

          const SizedBox(height: 14),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 14),

          Text("Vehicle", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                value: offer.busCount,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Buses",
                  prefixIcon: Icon(Icons.directions_bus),
                ),
                items: List.generate(8, (i) => i + 1)
                    .map((n) => DropdownMenuItem(value: n, child: Text("$n")))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  offer.busCount = v;
                  onChanged();
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<BusType>(
                value: offer.busType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Bus type",
                  prefixIcon: Icon(Icons.airline_seat_recline_normal),
                ),
                items: BusType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  offer.busType = v;
                  onChanged();
                },
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save),
                  label: const Text("Save draft"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Export PDF"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutesTableHeader extends StatelessWidget {
  const _RoutesTableHeader();

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);

    return Row(
      children: const [
        SizedBox(width: 105, child: Text("Date", style: headerStyle)),
        SizedBox(width: 12),
        Expanded(child: Text("Route", style: headerStyle)),
        SizedBox(width: 12),
        SizedBox(width: 70, child: Text("KM", style: headerStyle, textAlign: TextAlign.right)),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutesTableRow({
    required this.date,
    required this.route,
    required this.km,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 105, child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              route,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text(
              km == null ? "?" : km!.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: km == null ? cs.error : cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 66,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                ),
                const SizedBox(width: 6),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
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

  const _LocationAutoComplete({
    required this.controller,
    required this.suggestions,
    required this.onSubmit,
    required this.onPasteMulti,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (text) {
        final q = text.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return suggestions.where((s) => s.toLowerCase().contains(q)).take(10);
      },
      onSelected: (value) => controller.text = value,
      fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
        textCtrl.value = controller.value;

        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: "Location",
            prefixIcon: Icon(Icons.place),
          ),
          onSubmitted: (_) => onSubmit(),
          onChanged: (v) {
            if (v.contains("\n")) {
              final lines = v.split(RegExp(r"\r?\n"));
              controller.clear();
              onPasteMulti(lines);
            }
          },
        );
      },
    );
  }
}