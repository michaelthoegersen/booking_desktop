import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
import '../../state/role_labels.dart';
import '../../services/intensjonsavtale_pdf_service.dart';
import '../../services/email_service.dart';
import '../../widgets/contact_profile_dialog.dart';
import '../../widgets/mention_helpers.dart';
import '../../widgets/rich_text_field.dart';
import '../inventory/show_equipment_dialog.dart';

class MgmtGigDetailPage extends StatefulWidget {
  final String gigId;

  const MgmtGigDetailPage({super.key, required this.gigId});

  @override
  State<MgmtGigDetailPage> createState() => _MgmtGigDetailPageState();
}

class _MgmtGigDetailPageState extends State<MgmtGigDetailPage>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late TabController _tabCtrl;

  bool _loading = true;
  Map<String, dynamic>? _gig;

  List<Map<String, dynamic>> _shows = [];
  List<Map<String, dynamic>> _showTypes = [];
  List<Map<String, dynamic>> _companyMembers = []; // {user_id, name, status, section}
  String? _linkedOfferId; // gig_offer linked to this gig
  List<Map<String, dynamic>> _siblingGigs = []; // all gigs in multi-date offer
  // gig_id → list of show maps for each sibling gig (for PDF rendering)
  Map<String, List<Map<String, dynamic>>> _siblingShows = {};
  Map<String, dynamic>? _offerData; // the linked offer (for final_calc etc.)
  // Free-text extra cost lines from the linked offer (Ekstrakostnader). Loaded
  // for both single- and multi-date offers so they can be rendered on the
  // agreement; multi-date already gets them via final_calc, single-date needs
  // them passed explicitly to the legacy price summary.
  List<({String label, double amount})> _offerExtras = [];
  List<Map<String, dynamic>> _lineup = [];
  // showId → Set<userId> per section
  Map<String, Set<String>> _selectedSkarpByShow = {};
  Map<String, Set<String>> _selectedBassByShow = {};

  // Language for intensjonsavtale send dialog ('no' or 'en')
  String _intensjonLang = 'no';

  // Company pricing defaults — used as fallback for show prices
  // when a gig_shows row has price_is_custom = false.
  double _creoFeeMinimum = 5500;
  double _extraShowFee = 1500;


  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void didUpdateWidget(MgmtGigDetailPage old) {
    super.didUpdateWidget(old);
    if (old.gigId != widget.gigId) {
      _load();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final gig = await _sb
          .from('gigs')
          .select('*')
          .eq('id', widget.gigId)
          .maybeSingle();
      _gig = gig;

      final shows = await _sb
          .from('gig_shows')
          .select('*')
          .eq('gig_id', widget.gigId)
          .order('sort_order');
      _shows = List<Map<String, dynamic>>.from(shows);

      final types = await _sb
          .from('show_types')
          .select('*')
          .eq('active', true)
          .order('sort_order');
      _showTypes = List<Map<String, dynamic>>.from(types);

      // Load company pricing defaults (for CREO fallback on non-custom shows)
      try {
        final companyIdForPricing = _gig?['company_id'] as String?;
        if (companyIdForPricing != null) {
          final cRow = await _sb
              .from('companies')
              .select('pricing_defaults')
              .eq('id', companyIdForPricing)
              .maybeSingle();
          final pd = cRow?['pricing_defaults'] as Map<String, dynamic>? ?? {};
          _creoFeeMinimum =
              (pd['creo_fee_minimum'] as num?)?.toDouble() ?? _creoFeeMinimum;
          _extraShowFee =
              (pd['extra_show_fee'] as num?)?.toDouble() ?? _extraShowFee;
        }
      } catch (_) {}

      // Fetch team members from profiles (same source as Settings)
      final companyId = _gig?['company_id'] as String? ??
          activeCompanyNotifier.value?.id;
      if (companyId != null) {
        final members = await _sb
            .from('profiles')
            .select('id, name, role, section')
            .eq('company_id', companyId);

        // Auto-set all members to "available" for standalone rehearsals only.
        // Rehearsals that are part of a multi-date offer must be filled out
        // manually like a gig.
        final isRehearsal = (_gig?['type'] as String?) == 'rehearsal';
        bool isOfferRehearsal = false;
        if (isRehearsal) {
          final junctionRow = await _sb
              .from('gig_offer_gigs')
              .select('offer_id')
              .eq('gig_id', widget.gigId)
              .limit(1)
              .maybeSingle();
          if (junctionRow != null) {
            final offerId = junctionRow['offer_id'] as String?;
            if (offerId != null) {
              final siblings = await _sb
                  .from('gig_offer_gigs')
                  .select('gig_id')
                  .eq('offer_id', offerId);
              if ((siblings as List).length > 1) {
                isOfferRehearsal = true;
              }
            }
          }
        }
        if (isRehearsal && !isOfferRehearsal) {
          final existing = await _sb
              .from('gig_availability')
              .select('user_id')
              .eq('gig_id', widget.gigId);
          final existingIds = (existing as List)
              .map((e) => e['user_id'] as String)
              .toSet();
          final toInsert = (members as List)
              .map((m) => m['id'] as String)
              .where((uid) => !existingIds.contains(uid))
              .toList();
          if (toInsert.isNotEmpty) {
            await _sb.from('gig_availability').insert(
              toInsert
                  .map((uid) => {
                        'gig_id': widget.gigId,
                        'user_id': uid,
                        'status': 'available',
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                  .toList(),
            );
          }
        }

        var avail = await _sb
            .from('gig_availability')
            .select('user_id, status')
            .eq('gig_id', widget.gigId);

        // For multi-date offers: if this gig has no availability entries,
        // copy from a sibling gig that does
        if ((avail as List).isEmpty && _siblingGigs.length > 1) {
          for (final sg in _siblingGigs) {
            final sgId = sg['id'] as String;
            if (sgId == widget.gigId) continue;
            final siblingAvail = await _sb
                .from('gig_availability')
                .select('user_id, status')
                .eq('gig_id', sgId);
            if ((siblingAvail as List).isNotEmpty) {
              // Copy availability to this gig
              final rows = siblingAvail
                  .map((a) => {
                        'gig_id': widget.gigId,
                        'user_id': a['user_id'] as String,
                        'status': a['status'] as String,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                  .toList();
              await _sb.from('gig_availability').insert(rows);
              avail = await _sb
                  .from('gig_availability')
                  .select('user_id, status')
                  .eq('gig_id', widget.gigId);
              break;
            }
          }
        }

        final availMap = <String, String>{};
        for (final a in (avail as List)) {
          availMap[a['user_id'] as String] = a['status'] as String;
        }

        _companyMembers = (members as List).map((m) {
          final uid = m['id'] as String;
          return {
            'user_id': uid,
            'name': m['name'] as String? ?? '',
            'role': m['role'] as String? ?? 'bruker',
            'section': m['section'] as String?,
            'status': availMap[uid] ?? 'pending',
          };
        }).toList();
        _companyMembers.sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));

        // Load lineup (including show_id for per-show assignment)
        final lineupData = await _sb
            .from('gig_lineup')
            .select('user_id, section, show_id')
            .eq('gig_id', widget.gigId);
        _lineup = List<Map<String, dynamic>>.from(lineupData);
        _selectedSkarpByShow = {};
        _selectedBassByShow = {};
        for (final l in _lineup) {
          final showId = l['show_id'] as String? ?? '';
          if (l['section'] == 'skarp') {
            _selectedSkarpByShow.putIfAbsent(showId, () => {});
            _selectedSkarpByShow[showId]!.add(l['user_id'] as String);
          } else if (l['section'] == 'bass') {
            _selectedBassByShow.putIfAbsent(showId, () => {});
            _selectedBassByShow[showId]!.add(l['user_id'] as String);
          }
        }
      }

      // Check for linked gig offer
      final offerRow = await _sb
          .from('gig_offers')
          .select('id')
          .eq('gig_id', widget.gigId)
          .maybeSingle();
      _linkedOfferId = offerRow?['id'] as String?;
      // Fallback: check junction table for multi-date offers
      if (_linkedOfferId == null) {
        final junctionRow = await _sb
            .from('gig_offer_gigs')
            .select('offer_id')
            .eq('gig_id', widget.gigId)
            .limit(1)
            .maybeSingle();
        _linkedOfferId = junctionRow?['offer_id'] as String?;
      }

      // Load sibling gigs + offer data for multi-date offers
      _siblingGigs = [];
      _offerData = null;
      _offerExtras = [];
      if (_linkedOfferId != null) {
        // Always load the offer's extra cost lines (Ekstrakostnader), regardless
        // of single- vs multi-date, so they can appear on the agreement.
        try {
          final extrasRow = await _sb
              .from('gig_offers')
              .select('extras')
              .eq('id', _linkedOfferId!)
              .maybeSingle();
          final rawExtras = extrasRow?['extras'];
          if (rawExtras is List) {
            _offerExtras = rawExtras
                .whereType<Map>()
                .map((m) => (
                      label: (m['name'] as String? ?? '').trim(),
                      amount: (m['amount'] as num?)?.toDouble() ?? 0,
                    ))
                .where((e) => e.label.isNotEmpty && e.amount != 0)
                .toList();
          }
        } catch (e) {
          debugPrint('Load offer extras error: $e');
        }
        // Load the offer (final_calc + pricing params) for BOTH single- and
        // multi-date offers, so show prices use the offer's saved CREO/satser.
        _offerData = await _sb
            .from('gig_offers')
            .select('*')
            .eq('id', _linkedOfferId!)
            .maybeSingle();
        final junctionRows = await _sb
            .from('gig_offer_gigs')
            .select('gig_id')
            .eq('offer_id', _linkedOfferId!)
            .order('sort_order');
        final siblingIds = (junctionRows as List)
            .map((r) => r['gig_id'] as String)
            .toList();
        if (siblingIds.length > 1) {
          // Multi-date offer — load all sibling gigs
          final siblings = await _sb
              .from('gigs')
              .select('id, date_from, date_to, venue_name, city, country, type')
              .inFilter('id', siblingIds)
              .order('date_from', ascending: true);
          _siblingGigs = List<Map<String, dynamic>>.from(siblings);
          // Load shows per sibling gig (for PDF date-by-date breakdown)
          _siblingShows = {};
          if (siblingIds.isNotEmpty) {
            final allShows = await _sb
                .from('gig_shows')
                .select(
                    'gig_id, show_name, drummers, dancers, others, price, price_is_custom, sort_order')
                .inFilter('gig_id', siblingIds)
                .order('sort_order');
            for (final r in (allShows as List)) {
              final gid = r['gig_id'] as String;
              _siblingShows.putIfAbsent(gid, () => []).add(
                  Map<String, dynamic>.from(r as Map));
            }
          }
        }
      }

      // Adjust tab count now that we know if this is multi-date.
      // Tab count by type:
      //   gig (or rehearsal in multi-date offer): Info / Kontrakt / Chat (3)
      //   meeting:                                Info                 (1)
      //   rehearsal / other:                      Info / Chat          (2)
      final type = (_gig?['type'] as String?) ?? 'gig';
      final fullTabs = type == 'gig' ||
          (type == 'rehearsal' && _siblingGigs.length > 1);
      final desiredLength = fullTabs
          ? 3
          : type == 'meeting'
              ? 1
              : 2;
      if (_tabCtrl.length != desiredLength) {
        _tabCtrl.dispose();
        _tabCtrl = TabController(length: desiredLength, vsync: this);
      }
    } catch (e) {
      debugPrint('Gig detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------------
  // LINEUP HELPERS
  // -------------------------------------------------------------------------

  /// Toggle the current user's own availability for this gig (Kan / Kan ikke)
  /// — same flow as the mobile app uses.
  Future<void> _setMyAvailability(String status) async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    try {
      await _sb.from('gig_availability').upsert(
        {
          'gig_id': widget.gigId,
          'user_id': myId,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'gig_id,user_id',
      );
      // Patch the in-memory list so the UI reflects the change immediately.
      for (final m in _companyMembers) {
        if (m['user_id'] == myId) m['status'] = status;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Set availability error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    }
  }

  void _toggleLineupMember(String userId, String section, String showId) {
    setState(() {
      final map = section == 'skarp'
          ? _selectedSkarpByShow
          : _selectedBassByShow;
      map.putIfAbsent(showId, () => {});
      final set = map[showId]!;
      if (set.contains(userId)) {
        set.remove(userId);
        // Also remove any legacy "no-show" entry for the same user — the
        // UI only exposes per-show checkboxes, so a stale NULL-show entry
        // would otherwise survive the un-check and get re-inserted on save.
        if (showId.isNotEmpty) {
          map['']?.remove(userId);
        }
      } else {
        set.add(userId);
      }
    });
  }

  void _copyToAllShows(String fromShowId) {
    setState(() {
      final showIds = _shows.map((s) => s['id'] as String).toList();
      for (final section in ['skarp', 'bass']) {
        final map = section == 'skarp'
            ? _selectedSkarpByShow
            : _selectedBassByShow;
        final source = Set<String>.from(map[fromShowId] ?? {});
        for (final sid in showIds) {
          map[sid] = Set<String>.from(source);
        }
      }
    });
  }

  Future<void> _saveLineup(String section) async {
    final map = section == 'skarp'
        ? _selectedSkarpByShow
        : _selectedBassByShow;
    // Delete existing lineup for this section
    await _sb
        .from('gig_lineup')
        .delete()
        .eq('gig_id', widget.gigId)
        .eq('section', section);
    // Insert new — one row per (user, show). Dedup by (user_id, show_id)
    // because the unique constraint (gig_id, user_id, section, show_id)
    // treats NULL show_id values as equal — so if the same user ends up in
    // both `''` (no-show) and an actual show entry of the same map by
    // mistake, the second insert would conflict.
    // ALSO: if the gig has any real shows defined, never write rows with
    // show_id=NULL. The "no-show" bucket would otherwise be a stale legacy
    // artifact (it isn't visible in the per-show UI, so admins can't
    // un-check it) that keeps recreating itself on every save.
    final hasRealShows = _shows.isNotEmpty;
    final seen = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final entry in map.entries) {
      final showId = entry.key;
      if (hasRealShows && showId.isEmpty) continue; // skip legacy no-show
      for (final uid in entry.value) {
        final dedupKey = '$uid|${showId.isEmpty ? '' : showId}';
        if (!seen.add(dedupKey)) continue;
        rows.add({
          'gig_id': widget.gigId,
          'user_id': uid,
          'section': section,
          if (showId.isNotEmpty) 'show_id': showId,
        });
      }
    }
    if (rows.isNotEmpty) {
      await _sb.from('gig_lineup').insert(rows);
    }
  }

  Future<void> _saveAndToggleLock(String section) async {
    try {
      final field = section == 'skarp'
          ? 'lineup_locked_skarp'
          : 'lineup_locked_bass';
      final currentlyLocked = _gig?[field] == true;
      // Persist the current selection only when LOCKING. Unlocking must never
      // touch the saved lineup: _saveLineup deletes every row for the section
      // before re-inserting, so an empty or partial in-memory selection wiped
      // the whole lineup and all checkmarks disappeared.
      if (!currentlyLocked) {
        await _saveLineup(section);
      }
      await _sb
          .from('gigs')
          .update({field: !currentlyLocked})
          .eq('id', widget.gigId);
      // Only refresh the gig row (for lock flag) — don't reset lineup state
      final gig = await _sb
          .from('gigs')
          .select('*')
          .eq('id', widget.gigId)
          .single();
      if (mounted) setState(() => _gig = gig);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // PRICE HELPERS
  // -------------------------------------------------------------------------

  /// Effective (rendered) price for a gig_show row.
  ///
  /// - price_is_custom = true  → stored price wins
  /// - otherwise (auto)        → performers × CREO (main show gets
  ///                              creo_fee_minimum; extras get extra_show_fee)
  double _effectiveShowPrice(Map<String, dynamic> sh) {
    if (sh['price_is_custom'] == true) {
      return (sh['price'] as num?)?.toDouble() ?? 0;
    }
    final perf = ((sh['drummers'] as num?)?.toInt() ?? 0) +
        ((sh['dancers'] as num?)?.toInt() ?? 0) +
        ((sh['others'] as num?)?.toInt() ?? 0);
    // Main show = row with most performers (ties → first row).
    int mainPerf = 0;
    int mainId = -1;
    for (final row in _shows) {
      final p = ((row['drummers'] as num?)?.toInt() ?? 0) +
          ((row['dancers'] as num?)?.toInt() ?? 0) +
          ((row['others'] as num?)?.toInt() ?? 0);
      if (p > mainPerf) {
        mainPerf = p;
        mainId = _shows.indexOf(row);
      }
    }
    final isMain = _shows.indexOf(sh) == mainId;
    // Bruk tilbudets lagrede satser (Tilbud bestemmer), fall tilbake til
    // selskapets pricing_defaults kun hvis tilbudet mangler dem.
    final creo = (_offerData?['creo_fee_minimum'] as num?)?.toDouble() ??
        _creoFeeMinimum;
    final extra = (_offerData?['extra_show_fee'] as num?)?.toDouble() ??
        _extraShowFee;
    return perf * (isMain ? creo : extra);
  }

  double get _showsTotal =>
      _shows.fold(0, (s, sh) => s + _effectiveShowPrice(sh));

  double get _inearPrice =>
      (_gig?['inear_from_us'] == true)
          ? ((_gig?['inear_price'] as num?)?.toDouble() ?? 0)
          : 0;

  double get _transportPrice =>
      (_gig?['transport_price'] as num?)?.toDouble() ?? 0;

  double get _extraPrice =>
      (_gig?['extra_price'] as num?)?.toDouble() ?? 0;

  double get _total => _showsTotal + _inearPrice + _transportPrice + _extraPrice;

  // -------------------------------------------------------------------------
  // EDIT REHEARSAL
  // -------------------------------------------------------------------------

  Future<void> _editRehearsal() async {
    final g = _gig;
    if (g == null) return;

    final venueCtrl = TextEditingController(text: g['venue_name'] ?? '');
    final cityCtrl = TextEditingController(text: g['city'] ?? '');
    final countryCtrl = TextEditingController(text: g['country'] ?? 'NO');
    final responsibleCtrl = TextEditingController(text: g['responsible'] ?? '');
    final fromTimeCtrl = TextEditingController(text: g['meeting_time'] ?? '');
    final toTimeCtrl = TextEditingController(text: g['get_out_time'] ?? '');
    final notesCtrl = TextEditingController(text: g['notes_for_contract'] ?? '');
    var dateFrom = g['date_from'] != null ? DateTime.tryParse(g['date_from']) : null;
    var dateTo = g['date_to'] != null ? DateTime.tryParse(g['date_to']) : null;
    final df = DateFormat('dd.MM.yyyy');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rediger øvelse',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dates
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(dateFrom != null ? df.format(dateFrom!) : 'Dato fra'),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: dateFrom ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (d != null) setS(() => dateFrom = d);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(dateTo != null ? df.format(dateTo!) : 'Dato til'),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: dateFrom ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (d != null) setS(() => dateTo = d);
                                },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          // Location
                          Row(children: [
                            Expanded(flex: 2, child: TextField(
                              controller: venueCtrl,
                              decoration: const InputDecoration(labelText: 'Sted', isDense: true),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(
                              controller: cityCtrl,
                              decoration: const InputDecoration(labelText: 'By', isDense: true),
                            )),
                            const SizedBox(width: 8),
                            SizedBox(width: 70, child: TextField(
                              controller: countryCtrl,
                              decoration: const InputDecoration(labelText: 'Land', isDense: true),
                            )),
                          ]),
                          const SizedBox(height: 12),
                          TextField(
                            controller: responsibleCtrl,
                            decoration: const InputDecoration(labelText: 'Ansvarlig', isDense: true),
                          ),
                          const SizedBox(height: 12),
                          // Times
                          Row(children: [
                            Expanded(child: TextField(
                              controller: fromTimeCtrl,
                              decoration: const InputDecoration(labelText: 'Fra', isDense: true),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(
                              controller: toTimeCtrl,
                              decoration: const InputDecoration(labelText: 'Til', isDense: true),
                            )),
                          ]),
                          const SizedBox(height: 12),
                          // Notes
                          RichTextField(
                            controller: notesCtrl,
                            label: 'Dette skal vi gjøre på øvelsen',
                            minLines: 3,
                            maxLines: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Avbryt'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Lagre'),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    try {
      final n = (String s) => s.trim().isEmpty ? null : s.trim();
      await _sb.from('gigs').update({
        'venue_name': n(venueCtrl.text),
        'city': n(cityCtrl.text),
        'country': n(countryCtrl.text),
        'responsible': n(responsibleCtrl.text),
        'meeting_time': n(fromTimeCtrl.text),
        'get_out_time': n(toTimeCtrl.text),
        'notes_for_contract': n(notesCtrl.text),
        'date_from': dateFrom?.toIso8601String().substring(0, 10),
        'date_to': dateTo?.toIso8601String().substring(0, 10),
      }).eq('id', widget.gigId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }

    for (final c in [venueCtrl, cityCtrl, countryCtrl, responsibleCtrl,
                      fromTimeCtrl, toTimeCtrl, notesCtrl]) {
      c.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // DELETE GIG
  // -------------------------------------------------------------------------

  Future<void> _setLastAction(String action) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _sb.from('gigs').update({
      'last_action': {
        'type': action,
        'at': now,
        'by': _sb.auth.currentUser?.id,
      },
      'updated_at': now,
    }).eq('id', widget.gigId);
    _load();
  }

  Future<void> _confirmDeleteGig() async {
    final isRehearsal = (_gig?['type'] as String?) == 'rehearsal';
    final venue = _gig?['venue_name'] as String?;
    final dateFrom = _gig?['date_from'] as String?;
    final label = venue?.isNotEmpty == true ? venue! : (dateFrom ?? (isRehearsal ? 'denne øvelsen' : 'denne gigen'));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRehearsal ? 'Slett øvelse' : 'Slett gig'),
        content: Text(
          'Er du sikker på at du vil slette "$label"?\n\n'
          '${isRehearsal ? 'Øvelsen vil bli permanent slettet.' : 'Alle shows og crew tilknyttet gigen vil også slettes.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _sb.from('gigs').delete().eq('id', widget.gigId);
      if (mounted) context.go('/m/gigs');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // CANCEL / REOPEN
  // -------------------------------------------------------------------------

  Future<void> _cancelRehearsal() async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merk som avlyst'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Grunn for avlysning',
              hintText: 'Valgfritt',
              isDense: true,
            ),
            maxLines: 2,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Merk som avlyst'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final reason = reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
      await _sb.from('gigs').update({
        'status': 'cancelled',
        'cancellation_reason': reason,
      }).eq('id', widget.gigId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
    reasonCtrl.dispose();
  }

  Future<void> _reopenRehearsal() async {
    try {
      await _sb.from('gigs').update({
        'status': 'inquiry',
        'cancellation_reason': null,
      }).eq('id', widget.gigId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // SHOWS
  // -------------------------------------------------------------------------

  Future<void> _addShow() async {
    Map<String, dynamic>? selectedType;
    final priceCtrl = TextEditingController();
    final drumCtrl = TextEditingController();
    final danceCtrl = TextEditingController();
    final othersCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Legg til show'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  decoration: const InputDecoration(labelText: 'Show-type'),
                  value: selectedType,
                  items: _showTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setS(() {
                      selectedType = v;
                      if (v != null) {
                        priceCtrl.text = v['price']?.toString() ?? '0';
                        drumCtrl.text = v['drummers']?.toString() ?? '0';
                        danceCtrl.text = v['dancers']?.toString() ?? '0';
                        othersCtrl.text = v['others']?.toString() ?? '0';
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<RoleLabels>(
                  valueListenable: roleLabelsNotifier,
                  builder: (_, labels, __) => Row(
                    children: [
                      Expanded(child: _tf(drumCtrl, labels.role1,
                          keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(danceCtrl, labels.role2,
                          keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(othersCtrl, labels.role3,
                          keyboardType: TextInputType.number)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _tf(priceCtrl, 'Pris (kr)', keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedType == null) return;
                try {
                  await _sb.from('gig_shows').insert({
                    'gig_id': widget.gigId,
                    'show_type_id': selectedType!['id'],
                    'show_name': selectedType!['name'],
                    'drummers': int.tryParse(drumCtrl.text) ?? 0,
                    'dancers': int.tryParse(danceCtrl.text) ?? 0,
                    'others': int.tryParse(othersCtrl.text) ?? 0,
                    'price': double.tryParse(priceCtrl.text) ?? 0,
                    'sort_order': _shows.length,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Add show error: $e');
                }
              },
              child: const Text('Legg til'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteShow(String showId) async {
    try {
      await _sb.from('gig_shows').delete().eq('id', showId);
      await _load();
    } catch (e) {
      debugPrint('Delete show error: $e');
    }
  }

  /// Update (or reset) a gig_show row's price.
  ///
  /// [price] == 0 is treated as "reset to auto" and clears the custom flag.
  /// Any positive value marks the row as having a custom override.
  Future<void> _updateShowPrice(String showId, double price) async {
    try {
      final isCustom = price > 0;
      await _sb
          .from('gig_shows')
          .update({
            'price': isCustom ? price : 0,
            'price_is_custom': isCustom,
          })
          .eq('id', showId);
      await _load();
    } catch (e) {
      debugPrint('Update show price error: $e');
    }
  }


  // -------------------------------------------------------------------------
  // PDF / EMAIL
  // -------------------------------------------------------------------------

  bool get _isMultiDate => _siblingGigs.length > 1;

  /// Build calc lines from the offer's stored final_calc,
  /// or compute from offer params as fallback
  ({List<({String label, double amount})> lines, double total})? get _offerCalcFromDetail {
    if (_offerData == null) return null;

    // Try stored final_calc first
    final fc = _offerData!['final_calc'];
    if (fc != null) {
      final rawLines = fc['lines'] as List? ?? [];
      final lines = rawLines.map<({String label, double amount})>((l) {
        return (
          label: l['label'] as String? ?? '',
          amount: (l['amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      final total = (fc['total'] as num?)?.toDouble() ?? 0;
      return (lines: lines, total: total);
    }

    // Fallback: compute from offer params
    return _computeCalcFromOffer();
  }

  /// Compute calc lines from the offer's stored pricing params
  ({List<({String label, double amount})> lines, double total})? _computeCalcFromOffer() {
    if (_offerData == null) return null;
    final o = _offerData!;
    final numDates = _siblingGigs.length;
    final numRehearsalDates = _siblingGigs
        .where((g) => (g['type'] as String? ?? 'gig') == 'rehearsal')
        .length;
    final numPerformanceDates = numDates - numRehearsalDates;

    // Sum show prices across all sibling gigs' gig_shows
    // We only have _shows for this gig, but shows are typically the same across dates
    final showPricePerGig = _shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numPerformanceDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    // In-ear is a one-off cost — counted once regardless of date count.
    final inearTotal = inearIncluded ? inearPrice : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    // Main transport applies only to performance dates; rehearsal dates use
    // the separate rehearsal_transport parameter.
    final totalTransport =
        (transportPrice * numPerformanceDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final offerRehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
    final rehearsalCount =
        numRehearsalDates > 0 ? numRehearsalDates : offerRehearsalCount;
    final rehearsalPPP = (o['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0;
    final rehearsalTotal = (rehearsalPerformers * rehearsalCount * rehearsalPPP).toDouble();

    final markupPct = (o['markup_pct'] as num?)?.toDouble() ?? 0;
    final markupOnAll = o['markup_on_all'] == true;
    final completePct = markupPct / 2;
    final bookingPct = markupPct / 2;

    final subtotal = performerFees + inearTotal + totalTransport + rehearsalTotal;
    final markupBase = markupOnAll ? subtotal : performerFees;
    final completeKonto = markupBase * completePct;
    final bookingHonorar = markupBase * bookingPct;

    // Apply overrides if stored
    final ovJson = o['calc_overrides'];
    final ov = <String, double>{};
    if (ovJson is Map) {
      for (final e in ovJson.entries) {
        if (e.value is num) ov[e.key as String] = (e.value as num).toDouble();
      }
    }
    double ovv(String key, double calc) => ov.containsKey(key) ? ov[key]! : calc;

    final lines = <({String label, double amount})>[
      (label: 'Utøverhyrer', amount: ovv('performer_fees', performerFees)),
      (label: 'CompleteKonto', amount: ovv('complete_konto', completeKonto)),
      (label: 'BookingHonorar', amount: ovv('booking_honorar', bookingHonorar)),
      (label: 'In-Ear', amount: ovv('inear', inearTotal)),
      (label: 'Transport', amount: ovv('transport', totalTransport)),
      (label: 'Prøver', amount: ovv('rehearsal', rehearsalTotal)),
    ];

    final effectiveTotal = lines.fold<double>(0, (s, l) => s + l.amount);
    final total = ov.containsKey('total') ? ov['total']! : effectiveTotal;

    return (lines: lines.where((l) => l.amount > 0).toList(), total: total);
  }

  /// Build date entries for multi-date PDF
  Future<
          List<
              ({
                String date,
                String venue,
                bool isRehearsal,
                List<String> shows,
                List<double> showPrices,
                String getIn,
                String rehearsalTime,
                String performance,
                String getOut,
              })>>
      _pdfDateEntriesFromDetail() async {
    final df = DateFormat('dd.MM.yyyy');
    // Fetch fresh from DB rather than using the cached _siblingShows so we
    // always include price_is_custom and per-show performer counts even if
    // the cache was loaded before those columns were added to the load query.
    final siblingIds =
        _siblingGigs.map((g) => g['id'] as String).toList();
    final timesByGig = <String, Map<String, dynamic>>{};
    final showsByGig = <String, List<Map<String, dynamic>>>{};
    if (siblingIds.isNotEmpty) {
      try {
        final rows = await _sb
            .from('gigs')
            .select(
                'id, get_in_time, rehearsal_time, performance_time, get_out_time')
            .inFilter('id', siblingIds);
        for (final r in (rows as List)) {
          timesByGig[r['id'] as String] = Map<String, dynamic>.from(r as Map);
        }
      } catch (e) {
        debugPrint('Load sibling times error: $e');
      }
      try {
        final rows = await _sb
            .from('gig_shows')
            .select(
                'gig_id, show_name, drummers, dancers, others, price, price_is_custom, sort_order')
            .inFilter('gig_id', siblingIds)
            .order('sort_order');
        for (final r in (rows as List)) {
          final gid = r['gig_id'] as String;
          showsByGig
              .putIfAbsent(gid, () => [])
              .add(Map<String, dynamic>.from(r as Map));
        }
      } catch (e) {
        debugPrint('Load sibling shows error: $e');
      }
    }

    // Prefer the offer's own creo/extra fee values (they are stored on the
    // offer when it was created) rather than the company-level defaults that
    // may have changed since. This matches the preview path which reads
    // straight from offerData.
    final creoMin = (_offerData?['creo_fee_minimum'] as num?)?.toDouble() ??
        _creoFeeMinimum;
    final extraShow = (_offerData?['extra_show_fee'] as num?)?.toDouble() ??
        _extraShowFee;
    final entries = _siblingGigs.map((g) {
      final dateFrom = g['date_from'] as String?;
      final dateStr =
          dateFrom != null ? df.format(DateTime.parse(dateFrom)) : '';
      final venue = [
        g['venue_name'] as String? ?? '',
        g['city'] as String? ?? '',
        g['country'] as String? ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
      final isReh = (g['type'] as String? ?? 'gig') == 'rehearsal';
      // Compute per-show raw prices using main/extra CREO logic for this date.
      final rawShows = showsByGig[g['id'] as String] ?? const [];
      // Find main show index for this date (highest performer count).
      int mainIdx = 0;
      int mainPerf = -1;
      for (int i = 0; i < rawShows.length; i++) {
        final p = ((rawShows[i]['drummers'] as num?)?.toInt() ?? 0) +
            ((rawShows[i]['dancers'] as num?)?.toInt() ?? 0) +
            ((rawShows[i]['others'] as num?)?.toInt() ?? 0);
        if (p > mainPerf) {
          mainPerf = p;
          mainIdx = i;
        }
      }
      final showList = <String>[];
      final priceList = <double>[];
      for (int i = 0; i < rawShows.length; i++) {
        final sh = rawShows[i];
        final name = (sh['show_name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final perf = ((sh['drummers'] as num?)?.toInt() ?? 0) +
            ((sh['dancers'] as num?)?.toInt() ?? 0) +
            ((sh['others'] as num?)?.toInt() ?? 0);
        final isCustom = sh['price_is_custom'] == true;
        final rawPrice = isCustom
            ? ((sh['price'] as num?)?.toDouble() ?? 0)
            : perf * (i == mainIdx ? creoMin : extraShow);
        showList.add(name);
        priceList.add(rawPrice);
      }
      final t = timesByGig[g['id'] as String] ?? const {};
      return (
        date: dateStr,
        venue: venue,
        isRehearsal: isReh,
        shows: showList,
        showPrices: priceList,
        getIn: (t['get_in_time'] as String? ?? '').trim(),
        rehearsalTime: (t['rehearsal_time'] as String? ?? '').trim(),
        performance: (t['performance_time'] as String? ?? '').trim(),
        getOut: (t['get_out_time'] as String? ?? '').trim(),
        sortKey: dateFrom ?? '',
      );
    }).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return entries
        .map((e) => (
              date: e.date,
              venue: e.venue,
              isRehearsal: e.isRehearsal,
              shows: e.shows,
              showPrices: e.showPrices,
              getIn: e.getIn,
              rehearsalTime: e.rehearsalTime,
              performance: e.performance,
              getOut: e.getOut,
            ))
        .toList();
  }

  Future<void> _sendIntensjon() async {
    final emailCtrl =
        TextEditingController(text: _gig?['customer_email'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
        title: const Text('Send Intensjonsavtale'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isMultiDate
                  ? 'PDF-avtalen for alle ${_siblingGigs.length} datoer blir generert og sendt med aksepteringslenke.'
                  : 'PDF-avtalen blir generert og sendt med aksepteringslenke.'),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mottakere',
                  hintText: 'navn@firma.no, neste@firma.no',
                  helperText:
                      'Skill flere e-poster med komma, semikolon eller mellomrom.',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              const Text('Språk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'no', label: Text('Norsk')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {_intensjonLang},
                onSelectionChanged: (s) {
                  setSt(() => _intensjonLang = s.first);
                  setState(() {}); // also persist on parent state
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send'),
            onPressed: () async {
              Navigator.pop(ctx);
              ({Uint8List mainPdf, List<({String filename, Uint8List bytes, bool autoInclude})> riders, String title, String companyName})? result;
              try {
                // Single-date: legacy summary so the show is itemised as its
                // own line (visible price). Multi-date: offer's final_calc with
                // per-date breakdown. Matches the preview and signed PDF.
                final calc = _isMultiDate ? _offerCalcFromDetail : null;
                final entries =
                    _isMultiDate ? await _pdfDateEntriesFromDetail() : null;
                result = await IntensjonsavtalePdfService.generate(
                  gig: _gig!,
                  shows: _shows,
                  calcLines: calc?.lines,
                  calcTotal: calc?.total,
                  dateEntries: entries,
                  markupOnAll: _offerData?['markup_on_all'] == true,
                  lang: _intensjonLang,
                  extras: _offerExtras,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PDF-generering feilet: $e')),
                  );
                }
                return;
              }
              try {
                // For multi-date, use first sibling gig as canonical
                final canonicalGigId = _isMultiDate
                    ? _siblingGigs.first['id'] as String
                    : _gig!['id'] as String;
                final venue = _gig?['venue_name'] ?? 'gig';
                final dateFrom = _gig?['date_from'] ?? '';
                // Norwegian-formatted date (dd.MM.yyyy) for the email body and
                // subtitle — the raw value is ISO (yyyy-MM-dd).
                String dateFromFmt;
                try {
                  dateFromFmt = DateFormat('dd.MM.yyyy')
                      .format(DateTime.parse(dateFrom.toString()));
                } catch (_) {
                  dateFromFmt = dateFrom.toString();
                }
                final recipients = emailCtrl.text
                    .split(RegExp(r'[,;\s]+'))
                    .map((s) => s.trim())
                    .where((s) =>
                        s.isNotEmpty && s.contains('@') && s.contains('.'))
                    .toSet()
                    .toList();
                if (recipients.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Oppgi minst én gyldig e-postadresse.'),
                      ),
                    );
                  }
                  return;
                }

                // 1. Create agreement token (on canonical gig). Primary
                // customer_email keeps the first recipient for back-compat.
                final tokenRow = await _sb.from('agreement_tokens').insert({
                  'gig_id': canonicalGigId,
                  'customer_email': recipients.join(', '),
                  'status': 'pending',
                }).select('id, token').single();

                final token = tokenRow['token'] as String;
                final pdfPath = '$canonicalGigId/$token.pdf';

                // 2. Upload PDF to storage
                await _sb.storage.from('agreements').uploadBinary(
                  pdfPath,
                  result!.mainPdf,
                  fileOptions: const FileOptions(
                    contentType: 'application/pdf',
                    upsert: true,
                  ),
                );

                // 3. Update pdf_path on token
                await _sb.from('agreement_tokens')
                    .update({'pdf_path': pdfPath})
                    .eq('id', tokenRow['id']);

                // 4. Build accept URL
                final acceptUrl = 'https://tourflow-60890.web.app/accept.html?token=$token';

                // 5. Send HTML email with accept button + PDF attached
                final isEn = _intensjonLang == 'en';
                final subjectLabel = _isMultiDate
                    ? (isEn
                        ? '${_siblingGigs.length} dates'
                        : '${_siblingGigs.length} datoer')
                    : '$venue $dateFromFmt';
                final venueLabel = venue != ''
                    ? (isEn ? 'at $venue' : 'ved $venue')
                    : '';
                final dateLabel = dateFrom != ''
                    ? (isEn ? 'on $dateFromFmt' : 'den $dateFromFmt')
                    : '';
                final bodyDesc = _isMultiDate
                    ? (isEn
                        ? 'for ${_siblingGigs.length} agreed dates'
                        : 'for ${_siblingGigs.length} avtalte datoer')
                    : (isEn
                        ? 'for the engagement $venueLabel $dateLabel'
                        : 'for oppdrag $venueLabel $dateLabel');
                final emailTitle = isEn ? 'Letter of Intent' : 'Intensjonsavtale';
                final greeting = isEn ? 'Hello,' : 'Hei,';
                final introLine = isEn
                    ? 'Attached you will find the letter of intent $bodyDesc.'
                    : 'Vedlagt finner du intensjonsavtalen $bodyDesc.';
                final reviewLine = isEn
                    ? 'Please review the agreement in the attachment, and then accept it by clicking the button below:'
                    : 'Du kan lese gjennom avtalen i vedlegget, og deretter godta den ved å trykke på knappen under:';
                final acceptBtnLabel = isEn ? 'Accept agreement' : 'Aksepter avtale';
                final acceptDisclaimer = isEn
                    ? 'By accepting you confirm that you have read and agree to the terms of the letter of intent.'
                    : 'Ved å akseptere bekrefter du at du har lest og godtar betingelsene i intensjonsavtalen.';
                final signOff = isEn ? 'Best regards,' : 'Med vennlig hilsen,';
                String _fmtDateForFilename(String iso) {
                  try {
                    final dt = DateTime.parse(iso);
                    return DateFormat('dd.MM.yyyy').format(dt);
                  } catch (_) {
                    return iso;
                  }
                }
                final filenameTitle = result.title.isNotEmpty
                    ? result.title
                    : (isEn ? 'Letter of Intent' : 'Intensjonsavtale');
                final nonRehearsalGigs = _siblingGigs
                    .where((g) =>
                        (g['type'] as String? ?? 'gig') != 'rehearsal')
                    .toList();
                final filenameDate = _isMultiDate
                    ? nonRehearsalGigs
                        .map((g) =>
                            _fmtDateForFilename(g['date_from']?.toString() ?? ''))
                        .where((s) => s.isNotEmpty)
                        .join(' ')
                    : ((_gig?['type'] as String? ?? 'gig') == 'rehearsal'
                        ? ''
                        : _fmtDateForFilename(dateFrom.toString()));
                // Filename + subject share format: <Tittel> <Kundens firma> <dato(er)>
                // Language code and our own company name are intentionally
                // omitted — the title alone communicates the type, and the
                // customer cares about their own firma.
                final customerFirma =
                    (_gig?['customer_firma'] as String? ?? '').trim();
                final attFilename =
                    '${[filenameTitle, customerFirma, filenameDate].where((s) => s.isNotEmpty).join(' ')}.pdf';
                final customerAndDate = [customerFirma, filenameDate]
                    .where((s) => s.isNotEmpty)
                    .join(' ');
                final emailSubject = [filenameTitle, customerAndDate]
                    .where((s) => s.isNotEmpty)
                    .join(' — ');
                final htmlBody = '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #1a1a1a; padding: 24px 32px; border-radius: 8px 8px 0 0;">
    <h1 style="color: white; font-size: 20px; margin: 0;">$emailTitle</h1>
    <p style="color: #aaa; font-size: 14px; margin: 4px 0 0;">$subjectLabel</p>
  </div>
  <div style="background: #ffffff; padding: 28px 32px; border: 1px solid #eee; border-top: none;">
    <p style="font-size: 15px; line-height: 1.6; color: #333;">$greeting</p>
    <p style="font-size: 15px; line-height: 1.6; color: #333;">
      $introLine
    </p>
    <p style="font-size: 15px; line-height: 1.6; color: #333;">
      $reviewLine
    </p>
    <div style="text-align: center; margin: 28px 0;">
      <a href="$acceptUrl" style="display: inline-block; padding: 14px 36px; background: #16a34a; color: white; text-decoration: none; border-radius: 8px; font-size: 16px; font-weight: 600;">
        $acceptBtnLabel
      </a>
    </div>
    <p style="font-size: 13px; color: #888; line-height: 1.5;">
      $acceptDisclaimer
    </p>
  </div>
  <div style="padding: 16px 32px; background: #f9f9f9; border: 1px solid #eee; border-top: none; border-radius: 0 0 8px 8px;">
    <p style="font-size: 13px; color: #666; margin: 0;">$signOff<br><strong>Complete Drums / Stian Skog</strong></p>
  </div>
</div>
''';

                // Let user review/add attachments. All active riders are
                // listed; auto-included ones are pre-checked.
                final allRiders = result.riders.toList();
                final extraAttachments =
                    <({String filename, Uint8List bytes})>[];
                final riderSelected =
                    allRiders.map((r) => r.autoInclude).toList();

                final sendConfirmed = await showDialog<bool>(
                  context: context,
                  builder: (dlgCtx) => StatefulBuilder(
                    builder: (dlgCtx, setSt) => AlertDialog(
                      title: const Text('Vedlegg'),
                      content: SizedBox(
                        width: 420,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Intensjonsavtale-PDF vedlegges alltid.',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (allRiders.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text('Riders:', style: TextStyle(fontWeight: FontWeight.w700)),
                              ...allRiders.asMap().entries.map((e) => CheckboxListTile(
                                    value: riderSelected[e.key],
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(e.value.filename, style: const TextStyle(fontSize: 13)),
                                    onChanged: (v) => setSt(() => riderSelected[e.key] = v ?? false),
                                  )),
                            ],
                            if (extraAttachments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('Ekstra vedlegg:', style: TextStyle(fontWeight: FontWeight.w700)),
                              ...extraAttachments.map((a) => Padding(
                                    padding: const EdgeInsets.only(left: 8, top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.attach_file, size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(a.filename, style: const TextStyle(fontSize: 13))),
                                        IconButton(
                                          icon: const Icon(Icons.close, size: 14),
                                          onPressed: () => setSt(() => extraAttachments.remove(a)),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Legg til PDF', style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['pdf'],
                                  withData: true,
                                );
                                if (pick != null) {
                                  final f = pick.files.single;
                                  if (f.bytes != null) {
                                    setSt(() => extraAttachments.add(
                                          (filename: f.name, bytes: f.bytes!),
                                        ));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Avbryt')),
                        FilledButton.icon(
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                          onPressed: () => Navigator.pop(dlgCtx, true),
                        ),
                      ],
                    ),
                  ),
                );

                if (sendConfirmed != true) return;

                final attachments = <({String filename, Uint8List bytes})>[
                  (filename: attFilename, bytes: result.mainPdf),
                  for (int i = 0; i < allRiders.length; i++)
                    if (riderSelected[i])
                      (
                        filename: allRiders[i].filename,
                        bytes: allRiders[i].bytes,
                      ),
                  ...extraAttachments,
                ];
                final delivered = <String>[];
                final failed = <String>[];
                String? sendError;
                // Send to all recipients concurrently — independent addresses,
                // so no duplicate risk, and multiple recipients no longer add up
                // in wall-clock time.
                await Future.wait(recipients.map((rcpt) async {
                  try {
                    await EmailService.sendEmailWithAttachments(
                      to: rcpt,
                      subject: emailSubject,
                      body: htmlBody,
                      attachments: attachments,
                      isHtml: true,
                      companyId: _gig?['company_id'] as String?,
                    );
                    delivered.add(rcpt);
                  } catch (e) {
                    debugPrint('Send to $rcpt failed: $e');
                    failed.add(rcpt);
                    sendError = e.toString();
                  }
                }));
                // Log who actually got it as a single send-history entry.
                if (delivered.isNotEmpty) {
                  try {
                    await _sb.from('agreement_token_sends').insert({
                      'token_id': tokenRow['id'],
                      'recipients': delivered,
                      'sent_by': _sb.auth.currentUser?.id,
                    });
                  } catch (e) {
                    debugPrint('Log send history error: $e');
                  }
                }
                if (mounted) {
                  final summary = failed.isEmpty
                      ? (isEn
                          ? 'Sent to ${delivered.length} recipient(s).'
                          : 'Sendt til ${delivered.length} mottaker(e).')
                      : (isEn
                          ? 'Sent to ${delivered.length}; failed: ${failed.join(', ')}'
                          : 'Sendt til ${delivered.length}; feilet: ${failed.join(', ')}');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(sendError == null
                          ? summary
                          : '$summary\n\nÅrsak: $sendError'),
                      duration: Duration(
                          seconds: sendError == null ? 4 : 12),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sending feilet: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_gig == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gig ikke funnet'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/m/gigs'),
                child: const Text('Tilbake til gigs'),
              ),
            ],
          ),
        ),
      );
    }

    final dateFrom = _gig!['date_from'] as String?;
    final dateTo = _gig!['date_to'] as String?;
    final venue = _gig!['venue_name'] as String? ?? '';
    final city = _gig!['city'] as String? ?? '';
    final firma = _gig!['customer_firma'] as String? ?? '';
    final custName = _gig!['customer_name'] as String? ?? '';
    final status = _gig!['status'] as String? ?? 'inquiry';

    String dateLabel = '';
    if (dateFrom != null) {
      final df = DateFormat('dd.MM.yyyy');
      final from = df.format(DateTime.parse(dateFrom));
      if (dateTo != null && dateTo != dateFrom) {
        dateLabel = '$from – ${df.format(DateTime.parse(dateTo))}';
      } else {
        dateLabel = from;
      }
    }

    final title = [venue, city].where((s) => s.isNotEmpty).join(' · ');
    final customerLine = [firma, custName].where((s) => s.isNotEmpty).join(' — ');
    final gigType = _gig?['type'] as String? ?? 'gig';
    final isRehearsalInOffer = gigType == 'rehearsal' && _isMultiDate;
    final treatAsGig = gigType == 'gig' || isRehearsalInOffer;
    final rehearsalLabel = isRehearsalInOffer ? 'Prøve' : 'Øvelse';
    final cancellationReason = _gig?['cancellation_reason'] as String?;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb
          GestureDetector(
            onTap: () => context.go('/m/gigs'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  'Aktiviteter',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Main header row — matches tour detail style
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gigType == 'rehearsal'
                          ? (isRehearsalInOffer
                              ? '$rehearsalLabel${title.isNotEmpty ? ' · $title' : ''}'
                              : 'Øvelse')
                          : (title.isNotEmpty ? title : (dateLabel.isNotEmpty ? dateLabel : 'Gig')),
                      style: Theme.of(context).textTheme.headlineMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dateLabel.isNotEmpty)
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    if (gigType == 'rehearsal' && !isRehearsalInOffer && title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    if (customerLine.isNotEmpty && treatAsGig)
                      Text(
                        customerLine,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    if (status == 'cancelled' && cancellationReason != null && cancellationReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          cancellationReason,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (status == 'cancelled') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Avlyst',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (treatAsGig && status != 'cancelled')
                _GigStatusBadge(status: status),
              if (treatAsGig) ...[
                const SizedBox(width: 8),
                _linkedOfferId != null
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.request_quote_rounded, size: 16),
                        label: const Text('Rediger tilbud'),
                        onPressed: () => context.go('/m/offers/$_linkedOfferId'),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.request_quote_rounded, size: 16),
                        label: const Text('Opprett tilbud'),
                        onPressed: () => context.go('/m/offers/new?gigId=${_gig!['id']}'),
                      ),
              ],
              // Action button (Stian only)
              if (_sb.auth.currentUser?.email == 'stian@completedrums.no')
                PopupMenuButton<String>(
                  icon: const Icon(Icons.update, size: 20),
                  tooltip: 'Oppdater',
                  onSelected: (v) => _setLastAction(v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'Purret kunde', child: Text('Purret kunde')),
                    PopupMenuItem(value: 'Oppdatert', child: Text('Oppdatert')),
                  ],
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'edit') {
                    if (gigType == 'rehearsal' && !isRehearsalInOffer) {
                      _editRehearsal();
                    } else if (_linkedOfferId != null) {
                      context.go('/m/offers/$_linkedOfferId');
                    } else {
                      context.go('/m/offers/new?gigId=${widget.gigId}');
                    }
                  }
                  if (v == 'cancel') _cancelRehearsal();
                  if (v == 'reopen') _reopenRehearsal();
                  if (v == 'delete') _confirmDeleteGig();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(gigType == 'rehearsal'
                            ? (isRehearsalInOffer
                                ? 'Rediger tilbud'
                                : 'Rediger øvelse')
                            : 'Rediger'),
                      ],
                    ),
                  ),
                  if (status != 'cancelled')
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text('Merk som avlyst', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  if (status == 'cancelled')
                    const PopupMenuItem(
                      value: 'reopen',
                      child: Row(
                        children: [
                          Icon(Icons.replay, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Text('Gjenåpne', style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          gigType == 'rehearsal'
                              ? (isRehearsalInOffer
                                  ? 'Slett prøve'
                                  : 'Slett øvelse')
                              : 'Slett gig',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Tabs — standalone meetings only show Info. Standalone
          // rehearsals/annet get Info + Chat. Gigs (and offer-rehearsals
          // treated as gig) get the full Info / Kontrakt / Chat set.
          TabBar(
            controller: _tabCtrl,
            tabs: treatAsGig
                ? const [
                    Tab(text: 'Info'),
                    Tab(text: 'Kontrakt'),
                    Tab(text: 'Chat'),
                  ]
                : (_gig?['type'] as String? ?? 'gig') == 'meeting'
                    ? const [Tab(text: 'Info')]
                    : const [Tab(text: 'Info'), Tab(text: 'Chat')],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: !treatAsGig
                  ? [
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isMultiDate) ...[
                              _MultiDateBanner(
                                siblingGigs: _siblingGigs,
                                currentGigId: widget.gigId,
                                linkedOfferId: _linkedOfferId,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _InfoTab(gig: _gig!, onUpdated: _load),
                            // Rehearsals/møter/annet get the same Kan/Kan
                            // ikke (Skal/Skal ikke for rehearsals) self-
                            // availability card + counts as the mobile app.
                            if ((_gig?['type'] as String? ?? 'gig') !=
                                'meeting') ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18),
                                child: _AvailabilitySummary(
                                  gig: _gig!,
                                  companyMembers: _companyMembers,
                                  onSetMyAvailability: _setMyAvailability,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Second tab for rehearsals/annet — chat.
                      if ((_gig?['type'] as String? ?? 'gig') != 'meeting')
                        _ChatTab(gigId: widget.gigId),
                    ]
                  : [
                      // Combined Info tab with shows + crew
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isMultiDate) ...[
                              _MultiDateBanner(
                                siblingGigs: _siblingGigs,
                                currentGigId: widget.gigId,
                                linkedOfferId: _linkedOfferId,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _InfoTab(
                              gig: _gig!,
                              onUpdated: _load,
                              treatAsGig: treatAsGig,
                            ),
                            const SizedBox(height: 12),
                            _ShowsPrisTab(
                              gig: _gig!,
                              shows: _shows,
                              showTypes: _showTypes,
                              onAddShow: _addShow,
                              onDeleteShow: _deleteShow,
                              onUpdatePrice: _updateShowPrice,
                              effectivePriceFor: _effectiveShowPrice,
                              showsTotal: _showsTotal,
                              inearPrice: _inearPrice,
                              transportPrice: _transportPrice,
                              extraPrice: _extraPrice,
                              total: _total,
                              siblingGigs: _siblingGigs,
                              offerData: _offerData,
                              linkedOfferId: _linkedOfferId,
                            ),
                            const SizedBox(height: 12),
                            _CrewLineupTab(
                              companyMembers: _companyMembers,
                              gig: _gig!,
                              shows: _shows,
                              selectedSkarpByShow: _selectedSkarpByShow,
                              selectedBassByShow: _selectedBassByShow,
                              onToggleMember: _toggleLineupMember,
                              onSaveAndLock: _saveAndToggleLock,
                              onCopyToAllShows: _copyToAllShows,
                              onSetMyAvailability: _setMyAvailability,
                            ),
                          ],
                        ),
                      ),
                      _KontraktTab(
                        gig: _gig!,
                        shows: _shows,
                        total: _total,
                        onSend: _sendIntensjon,
                        siblingGigs: _siblingGigs,
                        offerData: _offerData,
                        offerExtras: _offerExtras,
                        linkedOfferId: _linkedOfferId,
                      ),
                      _ChatTab(gigId: widget.gigId),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// SHARED HELPERS
// ===========================================================================

Widget _tf(
  TextEditingController ctrl,
  String label, {
  int maxLines = 1,
  TextInputType keyboardType = TextInputType.text,
}) {
  return TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
  );
}

// ===========================================================================
// TAB 1 — INFO
// ===========================================================================

class _InfoTab extends StatefulWidget {
  final Map<String, dynamic> gig;
  final VoidCallback onUpdated;
  final bool treatAsGig;

  const _InfoTab({
    required this.gig,
    required this.onUpdated,
    this.treatAsGig = false,
  });

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic> get gig => widget.gig;

  Future<void> _editField(String label, String dbField, {bool multiline = false}) async {
    final current = gig[dbField]?.toString() ?? '';
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: multiline ? 8 : 1,
          decoration: InputDecoration(
            hintText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: multiline ? null : (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result != current) {
      await _sb.from('gigs').update({
        dbField: result.isEmpty ? null : result,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', gig['id']);
      setState(() => gig[dbField] = result.isEmpty ? null : result);
      widget.onUpdated();
    }
  }

  Future<void> _editBool(String label, String dbField) async {
    final current = gig[dbField] == true;
    await _sb.from('gigs').update({
      dbField: !current,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', gig['id']);
    setState(() => gig[dbField] = !current);
    widget.onUpdated();
  }

  Future<void> _editNumber(String label, String dbField) async {
    final current = gig[dbField]?.toString() ?? '';
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: label, border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Lagre')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result != current) {
      final numVal = num.tryParse(result);
      await _sb.from('gigs').update({
        dbField: result.isEmpty ? null : numVal ?? result,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', gig['id']);
      setState(() => gig[dbField] = result.isEmpty ? null : numVal ?? result);
      widget.onUpdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gigType = gig['type'] as String? ?? 'gig';
    final isGig = gigType == 'gig' || widget.treatAsGig;

    if (!isGig) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _editCard(cs, 'Sted', [
                  _EditField('Venue', 'venue_name'),
                  _EditField('By', 'city'),
                  _EditField('Land', 'country'),
                ]),
                _editCard(cs, 'Tider', [
                  _EditField('Fra', 'meeting_time'),
                  _EditField('Til', 'get_out_time'),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                _editCard(cs, 'Ansvarlig', [
                  _EditField('Navn', 'responsible'),
                ]),
                _editCard(cs, 'Notat', [
                  _EditField('Dette skal vi gjøre', 'notes_for_contract', multiline: true),
                ]),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _readOnlyCard(cs, 'Sted', [
                MapEntry('Venue', gig['venue_name']),
                MapEntry('By', gig['city']),
                MapEntry('Land', gig['country']),
              ]),
              _readOnlyCard(cs, 'Kunde', [
                MapEntry('Firma', gig['customer_firma']),
                MapEntry('Kontakt', gig['customer_name']),
                MapEntry('Telefon', gig['customer_phone']),
                MapEntry('E-post', gig['customer_email']),
                MapEntry('Org.nr', gig['customer_org_nr']),
                MapEntry('Adresse', gig['customer_address']),
                MapEntry('EHF', gig['invoice_on_ehf'] == true ? 'Ja' : null),
              ]),
              // Fakturamottaker — vis alternativ-feltene kun når "annen
              // fakturamottaker" er huket av i tilbudet; ellers bare "Samme
              // som Kunde".
              if (gig['alt_invoice_enabled'] == true)
                _editCard(cs, 'Fakturamottaker', [
                  _EditField('Bruk alternativ', 'alt_invoice_enabled',
                      isBool: true),
                  _EditField('Firma', 'alt_invoice_firma'),
                  _EditField('Kontakt', 'alt_invoice_name'),
                  _EditField('Telefon', 'alt_invoice_phone'),
                  _EditField('E-post', 'alt_invoice_email'),
                  _EditField('Org.nr', 'alt_invoice_org_nr'),
                  _EditField('Adresse', 'alt_invoice_address'),
                  _EditField('Faktura på EHF', 'alt_invoice_on_ehf',
                      isBool: true),
                ])
              else
                _readOnlyCard(cs, 'Fakturamottaker', const [
                  MapEntry('Mottaker', 'Samme som Kunde'),
                ]),
              _editCard(cs, 'Tider', [
                _EditField('Oppmøte', 'meeting_time'),
                _EditField('Get-in', 'get_in_time'),
                _EditField('Prøver', 'rehearsal_time'),
                _EditField('Opptreden', 'performance_time'),
                _EditField('Get-out', 'get_out_time'),
                _EditField('Notat', 'meeting_notes', multiline: true),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _readOnlyCard(cs, 'Scene', [
                MapEntry('Form', gig['stage_shape']),
                MapEntry('Størrelse', gig['stage_size']),
                MapEntry('Notat', gig['stage_notes']),
              ]),
              _readOnlyCard(cs, 'Teknikk', [
                MapEntry('In-ear fra oss', gig['inear_from_us'] == true ? 'Ja' : 'Nei'),
                if (gig['inear_from_us'] == true)
                  MapEntry('In-ear pris', 'kr ${NumberFormat('#,##0', 'nb_NO').format((gig['inear_price'] as num?)?.toDouble() ?? 0)}'),
                MapEntry('Playback fra oss', gig['playback_from_us'] != false ? 'Ja' : 'Nei'),
              ]),
              _editCard(cs, 'Notater', [
                _EditField('For kontrakt', 'notes_for_contract', multiline: true),
                _EditField('Fra arrangør', 'info_from_organizer', multiline: true),
                _EditField('Showbeskrivelse', 'show_desc', multiline: true),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _readOnlyCard(ColorScheme cs, String title, List<MapEntry<String, dynamic>> entries) {
    final nonEmpty = entries
        .where((e) => e.value?.toString().isNotEmpty ?? false)
        .toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...nonEmpty.map((e) => _InfoRow(label: e.key, value: e.value?.toString())),
        ],
      ),
    );
  }

  Widget _editCard(ColorScheme cs, String title, List<_EditField> fields) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...fields.map((f) => _buildEditRow(cs, f)),
        ],
      ),
    );
  }

  Widget _buildEditRow(ColorScheme cs, _EditField field) {
    final value = gig[field.dbField];
    String displayValue;

    if (field.isBool) {
      displayValue = value == true ? 'Ja' : 'Nei';
    } else if (field.isNumber && value != null) {
      displayValue = 'kr ${NumberFormat('#,##0', 'nb_NO').format((value as num).toDouble())}';
    } else {
      displayValue = value?.toString() ?? '';
    }

    if (displayValue.isEmpty && !field.isBool) {
      displayValue = '—';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        if (field.isBool) {
          _editBool(field.label, field.dbField);
        } else if (field.isNumber) {
          _editNumber(field.label, field.dbField);
        } else {
          _editField(field.label, field.dbField, multiline: field.multiline);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                field.label,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: field.multiline && displayValue != '—'
                  ? MarkdownText(displayValue)
                  : Text(
                      displayValue,
                      style: TextStyle(
                        fontSize: 13,
                        color: displayValue == '—' ? cs.onSurfaceVariant : null,
                      ),
                    ),
            ),
            Icon(Icons.edit, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _EditField {
  final String label;
  final String dbField;
  final bool multiline;
  final bool isBool;
  final bool isNumber;

  const _EditField(this.label, this.dbField, {
    this.multiline = false,
    this.isBool = false,
    this.isNumber = false,
  });
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool useMarkdown;

  const _InfoRow({required this.label, this.value, this.useMarkdown = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: useMarkdown
                ? MarkdownText(value!)
                : Text(
                    value!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// MULTI-DATE BANNER
// ===========================================================================

class _MultiDateBanner extends StatelessWidget {
  final List<Map<String, dynamic>> siblingGigs;
  final String? linkedOfferId;
  final String currentGigId;

  const _MultiDateBanner({
    required this.siblingGigs,
    required this.currentGigId,
    this.linkedOfferId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('dd.MM');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Tilbud med ${siblingGigs.length} datoer',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (linkedOfferId != null)
                TextButton.icon(
                  onPressed: () => context.go('/m/offers/$linkedOfferId'),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Rediger tilbud', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: siblingGigs.map((g) {
              final gId = g['id'] as String;
              final isCurrent = gId == currentGigId;
              final dateFrom = g['date_from'] as String?;
              final dateStr = dateFrom != null ? df.format(DateTime.parse(dateFrom)) : '?';
              final venue = g['venue_name'] as String? ?? '';
              final label = venue.isNotEmpty ? '$dateStr · $venue' : dateStr;

              final chip = Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isCurrent ? Colors.black : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color:
                        isCurrent ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
              );
              return isCurrent
                  ? chip
                  : InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.go('/m/gigs/$gId'),
                      child: chip,
                    );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// TAB 2 — SHOWS & PRIS
// ===========================================================================

class _ShowsPrisTab extends StatefulWidget {
  final Map<String, dynamic> gig;
  final List<Map<String, dynamic>> shows;
  final List<Map<String, dynamic>> showTypes;
  final VoidCallback onAddShow;
  final Future<void> Function(String id) onDeleteShow;
  final Future<void> Function(String id, double price) onUpdatePrice;
  final double Function(Map<String, dynamic> show) effectivePriceFor;
  final double showsTotal;
  final double inearPrice;
  final double transportPrice;
  final double extraPrice;
  final double total;
  final List<Map<String, dynamic>> siblingGigs;
  final Map<String, dynamic>? offerData;
  final String? linkedOfferId;

  const _ShowsPrisTab({
    required this.gig,
    required this.shows,
    required this.showTypes,
    required this.onAddShow,
    required this.onDeleteShow,
    required this.onUpdatePrice,
    required this.effectivePriceFor,
    required this.showsTotal,
    required this.inearPrice,
    required this.transportPrice,
    required this.extraPrice,
    required this.total,
    this.siblingGigs = const [],
    this.offerData,
    this.linkedOfferId,
  });

  @override
  State<_ShowsPrisTab> createState() => _ShowsPrisTabState();
}

class _ShowsPrisTabState extends State<_ShowsPrisTab> {
  final _nok = NumberFormat('#,##0', 'nb_NO');

  String _fmt(double v) => 'kr ${_nok.format(v)}';

  bool get _isMultiDate => widget.siblingGigs.length > 1;

  ({List<({String label, double amount})> lines, double total})? get _offerCalcLines {
    if (widget.offerData == null) return null;
    final fc = widget.offerData!['final_calc'];
    if (fc != null) {
      final rawLines = fc['lines'] as List? ?? [];
      // Intern visning — vis Utøverhyrer, CompleteKonto og BookingHonorar som
      // egne linjer (ikke slått sammen). Kunde-PDF er en egen kodesti.
      final lines = rawLines
          .map<({String label, double amount})>((l) => (
                label: l['label'] as String? ?? '',
                amount: (l['amount'] as num?)?.toDouble() ?? 0,
              ))
          .where((l) => l.amount > 0)
          .toList();
      final total = (fc['total'] as num?)?.toDouble() ?? 0;
      return (lines: lines, total: total);
    }
    // Fallback: compute from offer params
    return _computeFromOffer();
  }

  ({List<({String label, double amount})> lines, double total})? _computeFromOffer() {
    if (widget.offerData == null) return null;
    final o = widget.offerData!;
    final numDates = widget.siblingGigs.length;
    final numRehearsalDates = widget.siblingGigs
        .where((g) => (g['type'] as String? ?? 'gig') == 'rehearsal')
        .length;
    final numPerformanceDates = numDates - numRehearsalDates;

    final showPricePerGig = widget.shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numPerformanceDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    // In-ear is a one-off cost — counted once regardless of date count.
    final inearTotal = inearIncluded ? inearPrice : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    // Main transport applies only to performance dates; rehearsal dates use
    // the separate rehearsal_transport parameter.
    final totalTransport =
        (transportPrice * numPerformanceDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final offerRehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
    final rehearsalCount =
        numRehearsalDates > 0 ? numRehearsalDates : offerRehearsalCount;
    final rehearsalPPP = (o['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0;
    final rehearsalTotal = (rehearsalPerformers * rehearsalCount * rehearsalPPP).toDouble();

    final markupPct = (o['markup_pct'] as num?)?.toDouble() ?? 0;
    final markupOnAll = o['markup_on_all'] == true;
    final completePct = markupPct / 2;
    final bookingPct = markupPct / 2;

    final subtotal = performerFees + inearTotal + totalTransport + rehearsalTotal;
    final markupBase = markupOnAll ? subtotal : performerFees;

    final ovJson = o['calc_overrides'];
    final ov = <String, double>{};
    if (ovJson is Map) {
      for (final e in ovJson.entries) {
        if (e.value is num) ov[e.key as String] = (e.value as num).toDouble();
      }
    }

    double ovv(String key, double calc) => ov.containsKey(key) ? ov[key]! : calc;

    // Egne linjer for Utøverhyrer, CompleteKonto og BookingHonorar (ikke slått
    // sammen) — intern visning.
    final lines = <({String label, double amount})>[
      (label: 'Utøverhyrer', amount: ovv('performer_fees', performerFees)),
      (label: 'CompleteKonto',
          amount: ovv('complete_konto', markupBase * completePct)),
      (label: 'BookingHonorar',
          amount: ovv('booking_honorar', markupBase * bookingPct)),
      (label: 'In-Ear', amount: ovv('inear', inearTotal)),
      (label: 'Transport', amount: ovv('transport', totalTransport)),
      (label: 'Prøver', amount: ovv('rehearsal', rehearsalTotal)),
    ];

    final effectiveTotal = lines.fold<double>(0, (s, l) => s + l.amount);
    final total = ov.containsKey('total') ? ov['total']! : effectiveTotal;

    return (lines: lines.where((l) => l.amount > 0).toList(), total: total);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Shows',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (!_isMultiDate)
                FilledButton.icon(
                  onPressed: widget.onAddShow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Legg til show'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Shows table
          if (widget.shows.isEmpty)
            Text('Ingen shows lagt til ennå.',
                style: TextStyle(color: cs.onSurfaceVariant))
          else if (_isMultiDate)
            // Simplified shows list for multi-date offers — just names
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.shows.map((show) {
                final name = show['show_name'] as String? ?? '';
                return Chip(
                  label: Text(name, style: const TextStyle(fontSize: 13)),
                  backgroundColor: cs.surfaceContainerHigh,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: ValueListenableBuilder<RoleLabels>(
                      valueListenable: roleLabelsNotifier,
                      builder: (_, labels, __) => Row(
                        children: [
                          const Expanded(
                              flex: 3,
                              child: Text('Show',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12))),
                          SizedBox(
                              width: 70,
                              child: Text(labels.role1,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                  textAlign: TextAlign.center)),
                          SizedBox(
                              width: 70,
                              child: Text(labels.role2,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                  textAlign: TextAlign.center)),
                          SizedBox(
                              width: 70,
                              child: Text(labels.role3,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                  textAlign: TextAlign.center)),
                          const SizedBox(
                              width: 110,
                              child: Text('Pris',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                  textAlign: TextAlign.right)),
                          const SizedBox(width: 80),
                        ],
                      ),
                    ),
                  ),
                  // Rows
                  ...widget.shows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final show = entry.value;
                    final isLast = i == widget.shows.length - 1;
                    return _ShowRow(
                      show: show,
                      isLast: isLast,
                      effectivePrice: widget.effectivePriceFor(show),
                      onDelete: () => widget.onDeleteShow(show['id']),
                      onUpdatePrice: (p) =>
                          widget.onUpdatePrice(show['id'], p),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Price summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prisoppsummering',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (_offerCalcLines != null) ...[
                  ..._offerCalcLines!.lines.map((l) =>
                      _PriceRow(label: l.label, value: _fmt(l.amount))),
                  const Divider(height: 20),
                  _PriceRow(
                    label: _isMultiDate
                        ? 'TILBUD (${widget.siblingGigs.length} datoer)'
                        : 'TILBUD',
                    value: _fmt(_offerCalcLines!.total),
                    bold: true,
                  ),
                ] else ...[
                  _PriceRow(
                      label: 'Sum show', value: _fmt(widget.showsTotal)),
                  if (widget.inearPrice > 0)
                    _PriceRow(
                        label: 'In-ear', value: _fmt(widget.inearPrice)),
                  if (widget.transportPrice > 0)
                    _PriceRow(
                        label: 'Transport',
                        value: _fmt(widget.transportPrice)),
                  if (widget.extraPrice > 0)
                    _PriceRow(
                        label:
                            widget.gig['extra_desc'] as String? ?? 'Ekstra',
                        value: _fmt(widget.extraPrice)),
                  const Divider(height: 20),
                  _PriceRow(
                    label: 'TOTAL',
                    value: _fmt(widget.total),
                    bold: true,
                  ),
                ],
              ],
            ),
          ),
        ],
    );
  }
}

class _ShowRow extends StatefulWidget {
  final Map<String, dynamic> show;
  final bool isLast;
  final double effectivePrice;
  final VoidCallback onDelete;
  final Future<void> Function(double) onUpdatePrice;

  const _ShowRow({
    required this.show,
    required this.isLast,
    required this.effectivePrice,
    required this.onDelete,
    required this.onUpdatePrice,
  });

  @override
  State<_ShowRow> createState() => _ShowRowState();
}

class _ShowRowState extends State<_ShowRow> {
  late TextEditingController _priceCtrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final show = widget.show;
    final isCustom = show['price_is_custom'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(
                bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(show['show_name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${show['drummers'] ?? 0}',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${show['dancers'] ?? 0}',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${show['others'] ?? 0}',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 110,
            child: _editing
                ? TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: NumberFormat('#,##0', 'nb_NO')
                          .format(widget.effectivePrice),
                      helperText: 'Tom = auto (CREO)',
                      helperStyle: const TextStyle(fontSize: 10),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (v) async {
                      final p = double.tryParse(v.trim()) ?? 0;
                      await widget.onUpdatePrice(p);
                      setState(() => _editing = false);
                    },
                  )
                : GestureDetector(
                    onTap: () {
                      _priceCtrl.text = isCustom
                          ? ((show['price'] as num?)?.toDouble() ?? 0)
                              .toStringAsFixed(0)
                          : '';
                      setState(() => _editing = true);
                    },
                    child: Tooltip(
                      message: isCustom
                          ? 'Egendefinert pris. Trykk for å endre (tomt felt = auto).'
                          : 'Auto-beregnet fra CREO. Trykk for å overstyre.',
                      child: Text(
                        'kr ${NumberFormat('#,##0', 'nb_NO').format(widget.effectivePrice)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              isCustom ? FontStyle.normal : FontStyle.italic,
                          color: isCustom ? null : cs.onSurfaceVariant,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                        ),
                      ),
                    ),
                  ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              onPressed: () => showGigShowEquipmentDialog(
                context,
                gigShowId: show['id'] as String,
                showName: show['show_name'] as String? ?? 'Show',
              ),
              tooltip: 'Utstyr',
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Colors.red,
              onPressed: widget.onDelete,
              tooltip: 'Fjern',
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _PriceRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                fontSize: bold ? 15 : 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// TAB 3 — CREW
// ===========================================================================

class _CrewLineupTab extends StatelessWidget {
  final List<Map<String, dynamic>> companyMembers;
  final Map<String, dynamic> gig;
  final List<Map<String, dynamic>> shows;
  final Map<String, Set<String>> selectedSkarpByShow;
  final Map<String, Set<String>> selectedBassByShow;
  final void Function(String userId, String section, String showId) onToggleMember;
  final Future<void> Function(String section) onSaveAndLock;
  final void Function(String fromShowId) onCopyToAllShows;
  final Future<void> Function(String status) onSetMyAvailability;

  const _CrewLineupTab({
    required this.companyMembers,
    required this.gig,
    required this.shows,
    required this.selectedSkarpByShow,
    required this.selectedBassByShow,
    required this.onToggleMember,
    required this.onSaveAndLock,
    required this.onCopyToAllShows,
    required this.onSetMyAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final skarpMembers = companyMembers
        .where((m) => m['section'] == 'skarp')
        .toList();
    final bassMembers = companyMembers
        .where((m) => m['section'] == 'bass')
        .toList();
    final noSectionMembers = companyMembers
        .where((m) => m['section'] == null || m['section'] == '')
        .toList();

    final lockedSkarp = gig['lineup_locked_skarp'] == true;
    final lockedBass = gig['lineup_locked_bass'] == true;

    // Availability counts
    final availCount = companyMembers
        .where((m) => m['status'] == 'available')
        .length;
    final unavailCount = companyMembers
        .where((m) => m['status'] == 'unavailable')
        .length;
    final pendingCount = companyMembers
        .where((m) => m['status'] == 'pending')
        .length;

    final isRehearsal = (gig['type'] as String? ?? 'gig') == 'rehearsal';
    final yesLabel = isRehearsal ? 'Skal' : 'Kan';
    final noLabel = isRehearsal ? 'Skal ikke' : 'Kan ikke';
    final yesCount = isRehearsal ? '$availCount skal' : '$availCount kan';
    final noCount =
        isRehearsal ? '$unavailCount skal ikke' : '$unavailCount kan ikke';

    final myId = Supabase.instance.client.auth.currentUser?.id ?? '';
    Map<String, dynamic>? myMember;
    for (final m in companyMembers) {
      if (m['user_id'] == myId) {
        myMember = Map<String, dynamic>.from(m);
        break;
      }
    }
    final myStatus = (myMember?['status'] as String?) ?? 'pending';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Self-availability — same Kan/Kan ikke (Skal/Skal ikke on rehearsals)
        // pattern as the mobile app.
        if (myMember != null) ...[
          Text('Tilgjengelighet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AvailabilityButton(
                  label: yesLabel,
                  icon: Icons.check_circle,
                  color: Colors.green,
                  selected: myStatus == 'available',
                  onTap: () => onSetMyAvailability(
                      myStatus == 'available' ? 'pending' : 'available'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AvailabilityButton(
                  label: noLabel,
                  icon: Icons.cancel,
                  color: Colors.red,
                  selected: myStatus == 'unavailable',
                  onTap: () => onSetMyAvailability(
                      myStatus == 'unavailable' ? 'pending' : 'unavailable'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        Text('Lag', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        Row(
          children: [
            _availBadge(Icons.check_circle, Colors.green, yesCount),
            const SizedBox(width: 12),
            _availBadge(Icons.cancel, Colors.red, noCount),
            const SizedBox(width: 12),
            _availBadge(Icons.help_outline, Colors.grey,
                '$pendingCount ikke svart'),
          ],
        ),
        const SizedBox(height: 16),

        if (companyMembers.isEmpty)
          Text('Ingen medlemmer lagt til ennå.',
              style: TextStyle(color: cs.onSurfaceVariant))
        else if (shows.isNotEmpty) ...[
          // Gig-level lock buttons
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => onSaveAndLock('skarp'),
                icon: Icon(lockedSkarp ? Icons.lock_open : Icons.lock, size: 16),
                label: Text(lockedSkarp ? 'Lås opp Skarp' : 'Lås Skarp'),
                style: FilledButton.styleFrom(
                  backgroundColor: lockedSkarp ? Colors.orange : Colors.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => onSaveAndLock('bass'),
                icon: Icon(lockedBass ? Icons.lock_open : Icons.lock, size: 16),
                label: Text(lockedBass ? 'Lås opp Bass' : 'Lås Bass'),
                style: FilledButton.styleFrom(
                  backgroundColor: lockedBass ? Colors.orange : Colors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Per-show crew assignment ──
          for (final show in shows) ...[
            _buildShowBlock(
              context,
              show: show,
              skarpMembers: skarpMembers,
              bassMembers: bassMembers,
              noSectionMembers: noSectionMembers,
              lockedSkarp: lockedSkarp,
              lockedBass: lockedBass,
            ),
            const SizedBox(height: 20),
          ],
        ] else ...[
          // Fallback: no shows → assign per gig (showId = '')
          _buildSectionBlock(
            context,
            title: 'Skarp',
            color: Colors.purple,
            members: skarpMembers,
            selected: selectedSkarpByShow[''] ?? {},
            section: 'skarp',
            showId: '',
            locked: lockedSkarp,
          ),
          const SizedBox(height: 16),
          _buildSectionBlock(
            context,
            title: 'Bass',
            color: Colors.teal,
            members: bassMembers,
            selected: selectedBassByShow[''] ?? {},
            section: 'bass',
            showId: '',
            locked: lockedBass,
          ),
          if (noSectionMembers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionBlock(
              context,
              title: 'Ingen seksjon',
              color: Colors.grey,
              members: noSectionMembers,
              selected: const {},
              section: '',
              showId: '',
              locked: false,
              readOnly: true,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildShowBlock(
    BuildContext context, {
    required Map<String, dynamic> show,
    required List<Map<String, dynamic>> skarpMembers,
    required List<Map<String, dynamic>> bassMembers,
    required List<Map<String, dynamic>> noSectionMembers,
    required bool lockedSkarp,
    required bool lockedBass,
  }) {
    final cs = Theme.of(context).colorScheme;
    final showId = show['id'] as String;
    final showName = show['show_name'] as String? ?? 'Show';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(showName,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (shows.length > 1)
                TextButton.icon(
                  onPressed: () => onCopyToAllShows(showId),
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Kopier til alle shows',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionBlock(
            context,
            title: 'Skarp',
            color: Colors.purple,
            members: skarpMembers,
            selected: selectedSkarpByShow[showId] ?? {},
            section: 'skarp',
            showId: showId,
            locked: lockedSkarp,
          ),
          const SizedBox(height: 12),
          _buildSectionBlock(
            context,
            title: 'Bass',
            color: Colors.teal,
            members: bassMembers,
            selected: selectedBassByShow[showId] ?? {},
            section: 'bass',
            showId: showId,
            locked: lockedBass,
          ),
          if (noSectionMembers.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionBlock(
              context,
              title: 'Ingen seksjon',
              color: Colors.grey,
              members: noSectionMembers,
              selected: const {},
              section: '',
              showId: showId,
              locked: false,
              readOnly: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionBlock(
    BuildContext context, {
    required String title,
    required Color color,
    required List<Map<String, dynamic>> members,
    required Set<String> selected,
    required String section,
    required String showId,
    required bool locked,
    bool readOnly = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    // Count members who are either admin-selected OR self-checked as available
    final effectiveCount = members.where((m) {
      final uid = m['user_id'] as String;
      return selected.contains(uid) || m['status'] == 'available';
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$title ($effectiveCount)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const Spacer(),
            // Only show lock button on the top-level (not per-show) or when no shows
            if (!readOnly && section.isNotEmpty && shows.isEmpty)
              FilledButton.icon(
                onPressed: () => onSaveAndLock(section),
                icon: Icon(locked ? Icons.lock_open : Icons.lock, size: 16),
                label: Text(locked ? 'Lås opp' : 'Lås'),
                style: FilledButton.styleFrom(
                  backgroundColor: locked ? Colors.orange : color,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text('Ingen medlemmer i denne seksjonen.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: members.asMap().entries.map((entry) {
                final i = entry.key;
                final m = entry.value;
                final isLast = i == members.length - 1;
                final uid = m['user_id'] as String;

                IconData statusIcon;
                Color statusColor;
                switch (m['status'] as String?) {
                  case 'available':
                    statusIcon = Icons.check_circle;
                    statusColor = Colors.green;
                    break;
                  case 'unavailable':
                    statusIcon = Icons.cancel;
                    statusColor = Colors.red;
                    break;
                  default:
                    statusIcon = Icons.help_outline;
                    statusColor = Colors.grey;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      if (!readOnly && section.isNotEmpty)
                        Checkbox(
                          value: selected.contains(uid),
                          onChanged: locked
                              ? null
                              : (_) => onToggleMember(uid, section, showId),
                          activeColor: color,
                        ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => ContactProfileDialog.show(
                            context,
                            contactId: uid,
                            contactName:
                                (m['name'] as String?) ?? 'Ukjent',
                            avatarUrl: m['avatar_url'] as String?,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Text(
                              (m['name'] as String?) ?? 'Ukjent',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _availBadge(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// TAB 4 — KONTRAKT
// ===========================================================================

class _KontraktTab extends StatefulWidget {
  final Map<String, dynamic> gig;
  final List<Map<String, dynamic>> shows;
  final double total;
  final Future<void> Function() onSend;
  final List<Map<String, dynamic>> siblingGigs;
  final Map<String, dynamic>? offerData;
  final List<({String label, double amount})> offerExtras;
  final String? linkedOfferId;

  const _KontraktTab({
    required this.gig,
    required this.shows,
    required this.total,
    required this.onSend,
    this.siblingGigs = const [],
    this.offerData,
    this.offerExtras = const [],
    this.linkedOfferId,
  });

  @override
  State<_KontraktTab> createState() => _KontraktTabState();
}

class _KontraktTabState extends State<_KontraktTab> {
  final _sb = Supabase.instance.client;
  Uint8List? _pdfBytes;
  bool _generating = true;
  bool _sending = false;

  // Agreement status
  Map<String, dynamic>? _agreement;
  bool _approving = false;
  bool _refreshingAgreement = false;
  // Full send history across every agreement_token for this gig.
  List<Map<String, dynamic>> _sendHistory = [];
  // Poll for status updates so the "Godkjenn" button shows up automatically
  // after the customer accepts (no manual page reload required).
  Timer? _agreementPollTimer;

  @override
  void initState() {
    super.initState();
    _buildPdf();
    _loadAgreement();
    _agreementPollTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadAgreement());
  }

  @override
  void dispose() {
    _agreementPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_KontraktTab old) {
    super.didUpdateWidget(old);
    if (old.gig != widget.gig || old.shows != widget.shows) {
      _buildPdf();
    }
  }

  bool get _isMultiDate => widget.siblingGigs.length > 1;

  String _buildSignedFilename(
    ({Uint8List mainPdf, List<({String filename, Uint8List bytes, bool autoInclude})> riders, String title, String companyName}) result,
    String fallbackDate,
  ) {
    String fmt(String iso) {
      try {
        return DateFormat('dd.MM.yyyy').format(DateTime.parse(iso));
      } catch (_) {
        return iso;
      }
    }
    final title =
        result.title.isNotEmpty ? result.title : 'Intensjonsavtale';
    final customerFirma =
        (widget.gig['customer_firma'] as String? ?? '').trim();
    final dates = _isMultiDate
        ? widget.siblingGigs
            .where((g) => (g['type'] as String? ?? 'gig') != 'rehearsal')
            .map((g) => fmt(g['date_from']?.toString() ?? ''))
            .where((s) => s.isNotEmpty)
            .join(' ')
        : ((widget.gig['type'] as String? ?? 'gig') == 'rehearsal'
            ? ''
            : fmt(fallbackDate));
    final parts = ['Signert', title, customerFirma, dates]
        .where((s) => s.isNotEmpty)
        .toList();
    return '${parts.join(' ')}.pdf';
  }

  /// Build calc lines from offer's final_calc or compute from params
  ({List<({String label, double amount})> lines, double total})? get _offerCalc {
    if (widget.offerData == null) return null;

    // Try stored final_calc first
    final fc = widget.offerData!['final_calc'];
    if (fc != null) {
      final rawLines = fc['lines'] as List? ?? [];
      final lines = rawLines.map<({String label, double amount})>((l) {
        return (
          label: l['label'] as String? ?? '',
          amount: (l['amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      final total = (fc['total'] as num?)?.toDouble() ?? 0;
      return (lines: lines, total: total);
    }

    // Fallback: compute from offer params
    return _computeCalcFromOffer();
  }

  ({List<({String label, double amount})> lines, double total})? _computeCalcFromOffer() {
    if (widget.offerData == null) return null;
    final o = widget.offerData!;
    final numDates = widget.siblingGigs.length;
    final numRehearsalDates = widget.siblingGigs
        .where((g) => (g['type'] as String? ?? 'gig') == 'rehearsal')
        .length;
    final numPerformanceDates = numDates - numRehearsalDates;

    final showPricePerGig = widget.shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numPerformanceDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    // In-ear is a one-off cost — counted once regardless of date count.
    final inearTotal = inearIncluded ? inearPrice : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    // Main transport applies only to performance dates; rehearsal dates use
    // the separate rehearsal_transport parameter.
    final totalTransport =
        (transportPrice * numPerformanceDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final offerRehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
    final rehearsalCount =
        numRehearsalDates > 0 ? numRehearsalDates : offerRehearsalCount;
    final rehearsalPPP = (o['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0;
    final rehearsalTotal = (rehearsalPerformers * rehearsalCount * rehearsalPPP).toDouble();

    final markupPct = (o['markup_pct'] as num?)?.toDouble() ?? 0;
    final markupOnAll = o['markup_on_all'] == true;
    final completePct = markupPct / 2;
    final bookingPct = markupPct / 2;

    final subtotal = performerFees + inearTotal + totalTransport + rehearsalTotal;
    final markupBase = markupOnAll ? subtotal : performerFees;
    final completeKonto = markupBase * completePct;
    final bookingHonorar = markupBase * bookingPct;

    final ovJson = o['calc_overrides'];
    final ov = <String, double>{};
    if (ovJson is Map) {
      for (final e in ovJson.entries) {
        if (e.value is num) ov[e.key as String] = (e.value as num).toDouble();
      }
    }
    double ovv(String key, double calc) => ov.containsKey(key) ? ov[key]! : calc;

    final lines = <({String label, double amount})>[
      (label: 'Utøverhyrer', amount: ovv('performer_fees', performerFees)),
      (label: 'CompleteKonto', amount: ovv('complete_konto', completeKonto)),
      (label: 'BookingHonorar', amount: ovv('booking_honorar', bookingHonorar)),
      (label: 'In-Ear', amount: ovv('inear', inearTotal)),
      (label: 'Transport', amount: ovv('transport', totalTransport)),
      (label: 'Prøver', amount: ovv('rehearsal', rehearsalTotal)),
    ];

    final effectiveTotal = lines.fold<double>(0, (s, l) => s + l.amount);
    final total = ov.containsKey('total') ? ov['total']! : effectiveTotal;

    return (lines: lines.where((l) => l.amount > 0).toList(), total: total);
  }

  /// Build date entries for multi-date PDF (fetches per-date shows + times)
  Future<
          List<
              ({
                String date,
                String venue,
                bool isRehearsal,
                List<String> shows,
                List<double> showPrices,
                String getIn,
                String rehearsalTime,
                String performance,
                String getOut,
              })>>
      _pdfDateEntries() async {
    final df = DateFormat('dd.MM.yyyy');
    final siblingIds =
        widget.siblingGigs.map((g) => g['id'] as String).toList();
    // List of (name, raw_price) per gig — price uses main/extra CREO logic.
    final showsByGig = <String, List<({String name, double price})>>{};
    final timesByGig = <String, Map<String, dynamic>>{};
    // Pull creo/extra fee from offer (falls back to widget-level defaults).
    final creoMin =
        (widget.offerData?['creo_fee_minimum'] as num?)?.toDouble() ?? 5500.0;
    final extraShow =
        (widget.offerData?['extra_show_fee'] as num?)?.toDouble() ?? 1500.0;
    if (siblingIds.isNotEmpty) {
      try {
        final rows = await _sb
            .from('gig_shows')
            .select(
                'gig_id, show_name, drummers, dancers, others, price, price_is_custom, sort_order')
            .inFilter('gig_id', siblingIds)
            .order('sort_order');
        // Group raw rows per gig so we can determine per-date main show.
        final rawByGig = <String, List<Map<String, dynamic>>>{};
        for (final r in (rows as List)) {
          final gid = r['gig_id'] as String;
          rawByGig.putIfAbsent(gid, () => []).add(Map<String, dynamic>.from(r));
        }
        for (final entry in rawByGig.entries) {
          final gid = entry.key;
          final list = entry.value;
          // Find main show (highest performer count) for this date.
          int mainIdx = 0;
          int mainPerf = -1;
          for (int i = 0; i < list.length; i++) {
            final perf = ((list[i]['drummers'] as num?)?.toInt() ?? 0) +
                ((list[i]['dancers'] as num?)?.toInt() ?? 0) +
                ((list[i]['others'] as num?)?.toInt() ?? 0);
            if (perf > mainPerf) {
              mainPerf = perf;
              mainIdx = i;
            }
          }
          for (int i = 0; i < list.length; i++) {
            final sh = list[i];
            final name = (sh['show_name'] as String? ?? '').trim();
            if (name.isEmpty) continue;
            final perf = ((sh['drummers'] as num?)?.toInt() ?? 0) +
                ((sh['dancers'] as num?)?.toInt() ?? 0) +
                ((sh['others'] as num?)?.toInt() ?? 0);
            final isCustom = sh['price_is_custom'] == true;
            final rawPrice = isCustom
                ? ((sh['price'] as num?)?.toDouble() ?? 0)
                : perf * (i == mainIdx ? creoMin : extraShow);
            showsByGig.putIfAbsent(gid, () => []).add((
              name: name,
              price: rawPrice,
            ));
          }
        }
      } catch (e) {
        debugPrint('Load sibling shows error: $e');
      }
      try {
        final rows = await _sb
            .from('gigs')
            .select(
                'id, get_in_time, rehearsal_time, performance_time, get_out_time')
            .inFilter('id', siblingIds);
        for (final r in (rows as List)) {
          timesByGig[r['id'] as String] = Map<String, dynamic>.from(r as Map);
        }
      } catch (e) {
        debugPrint('Load sibling times error: $e');
      }
    }
    final entries = widget.siblingGigs.map((g) {
      final dateFrom = g['date_from'] as String?;
      final dateStr =
          dateFrom != null ? df.format(DateTime.parse(dateFrom)) : '';
      final venue = [
        g['venue_name'] as String? ?? '',
        g['city'] as String? ?? '',
        g['country'] as String? ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
      final isReh = (g['type'] as String? ?? 'gig') == 'rehearsal';
      final t = timesByGig[g['id'] as String] ?? const {};
      final gigShows = showsByGig[g['id'] as String] ?? const [];
      return (
        date: dateStr,
        venue: venue,
        isRehearsal: isReh,
        shows: gigShows.map((s) => s.name).toList(),
        showPrices: gigShows.map((s) => s.price).toList(),
        getIn: (t['get_in_time'] as String? ?? '').trim(),
        rehearsalTime: (t['rehearsal_time'] as String? ?? '').trim(),
        performance: (t['performance_time'] as String? ?? '').trim(),
        getOut: (t['get_out_time'] as String? ?? '').trim(),
        sortKey: dateFrom ?? '',
      );
    }).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return entries
        .map((e) => (
              date: e.date,
              venue: e.venue,
              isRehearsal: e.isRehearsal,
              shows: e.shows,
              showPrices: e.showPrices,
              getIn: e.getIn,
              rehearsalTime: e.rehearsalTime,
              performance: e.performance,
              getOut: e.getOut,
            ))
        .toList();
  }

  Future<void> _buildPdf() async {
    if (mounted) setState(() => _generating = true);
    try {
      // Single-date uses the legacy price summary so the show is itemised as
      // its own line; multi-date uses the offer's final_calc with per-date
      // breakdown. Matches the emailed contract and the signed customer PDF.
      final calc = _isMultiDate ? _offerCalc : null;
      final entries = _isMultiDate ? await _pdfDateEntries() : null;
      final result = await IntensjonsavtalePdfService.generate(
        gig: widget.gig,
        shows: widget.shows,
        calcLines: calc?.lines,
        calcTotal: calc?.total,
        dateEntries: entries,
        markupOnAll: widget.offerData?['markup_on_all'] == true,
        extras: widget.offerExtras,
      );
      if (mounted) setState(() => _pdfBytes = result.mainPdf);
    } catch (e) {
      debugPrint('PDF build error: $e');
    }
    if (mounted) setState(() => _generating = false);
  }

  Future<void> _loadAgreement() async {
    try {
      final gigId = widget.gig['id'] as String?;
      if (gigId == null) return;

      // For multi-date offers, check agreement on any sibling gig
      final gigIds = _isMultiDate
          ? widget.siblingGigs.map((g) => g['id'] as String).toList()
          : [gigId];

      // Prefer the most recent approved/accepted token over a newer pending
      // one — re-sending creates a fresh pending token that would otherwise
      // mask an existing customer acceptance.
      final allTokens = await _sb
          .from('agreement_tokens')
          .select()
          .inFilter('gig_id', gigIds)
          .order('created_at', ascending: false);
      final tokenList = List<Map<String, dynamic>>.from(allTokens as List);
      Map<String, dynamic>? row;
      for (final r in tokenList) {
        if (r['status'] == 'approved') { row = r; break; }
      }
      if (row == null) {
        for (final r in tokenList) {
          if (r['status'] == 'accepted') { row = r; break; }
        }
      }
      row ??= tokenList.isNotEmpty ? tokenList.first : null;

      // Pull the full send history (every send event across every token for
      // this gig / sibling group, newest first).
      List<Map<String, dynamic>> sends = [];
      try {
        final tokenIdRows = await _sb
            .from('agreement_tokens')
            .select('id')
            .inFilter('gig_id', gigIds);
        final tokenIds = (tokenIdRows as List)
            .map((r) => r['id'] as String)
            .toList();
        if (tokenIds.isNotEmpty) {
          final sendRows = await _sb
              .from('agreement_token_sends')
              .select('recipients, sent_at, sent_by')
              .inFilter('token_id', tokenIds)
              .order('sent_at', ascending: false);
          sends = List<Map<String, dynamic>>.from(sendRows as List);
        }
      } catch (e) {
        debugPrint('Load send history error: $e');
      }

      if (mounted) {
        setState(() {
          _agreement = row;
          _sendHistory = sends;
        });
      }
    } catch (e) {
      debugPrint('Load agreement error: $e');
    }
  }

  Future<void> _approveAgreement() async {
    if (_agreement == null) return;
    setState(() => _approving = true);
    try {
      final myId = _sb.auth.currentUser?.id;

      // Update agreement status
      await _sb.from('agreement_tokens').update({
        'status': 'approved',
        'approved_at': DateTime.now().toIso8601String(),
        'approved_by': myId,
      }).eq('id', _agreement!['id']);

      // Update ALL gigs + offer status to confirmed
      if (_isMultiDate) {
        for (final g in widget.siblingGigs) {
          await _sb.from('gigs').update({
            'status': 'confirmed',
          }).eq('id', g['id']);
        }
        if (widget.linkedOfferId != null) {
          await _sb.from('gig_offers').update({
            'status': 'confirmed',
          }).eq('id', widget.linkedOfferId!);
        }
      } else {
        final gigId = widget.gig['id'] as String?;
        if (gigId != null) {
          await _sb.from('gigs').update({
            'status': 'confirmed',
          }).eq('id', gigId);
          await _sb.from('gig_offers').update({
            'status': 'confirmed',
          }).eq('gig_id', gigId);
        }
      }

      // Generate signed PDF
      final acceptedName = _agreement!['accepted_name'] as String? ?? '';
      final acceptedAt = _agreement!['accepted_at'] as String?;
      // accepted_at is timestamptz (UTC) — to local time first, so a
      // signature after 22:00 norsk tid isn't stamped with the day before.
      final acceptedDate = acceptedAt != null
          ? DateFormat('dd.MM.yyyy')
              .format(DateTime.parse(acceptedAt).toLocal())
          : DateFormat('dd.MM.yyyy').format(DateTime.now());
      final approvedDate = DateFormat('dd.MM.yyyy').format(DateTime.now());

      final calc = _isMultiDate ? _offerCalc : null;
      final entries = _isMultiDate ? await _pdfDateEntries() : null;
      final signedResult = await IntensjonsavtalePdfService.generate(
        gig: widget.gig,
        shows: widget.shows,
        customerSignature: acceptedName,
        customerSignatureDate: acceptedDate,
        companySignature: 'Stian Skog',
        companySignatureDate: approvedDate,
        calcLines: calc?.lines,
        calcTotal: calc?.total,
        dateEntries: entries,
        markupOnAll: widget.offerData?['markup_on_all'] == true,
        extras: widget.offerExtras,
      );

      // Send signed PDF to customer
      final customerEmail = _agreement!['customer_email'] as String? ?? '';
      final venue = widget.gig['venue_name'] ?? '';
      final dateFrom = widget.gig['date_from'] ?? '';
      String fmtDate(String iso) {
        try {
          return DateFormat('dd.MM.yyyy').format(DateTime.parse(iso));
        } catch (_) {
          return iso;
        }
      }
      final signedTitle = signedResult.title.isNotEmpty
          ? signedResult.title
          : 'Intensjonsavtale';
      final signedDates = _isMultiDate
          ? widget.siblingGigs
              .where((g) => (g['type'] as String? ?? 'gig') != 'rehearsal')
              .map((g) => fmtDate(g['date_from']?.toString() ?? ''))
              .where((s) => s.isNotEmpty)
              .join(' ')
          : ((widget.gig['type'] as String? ?? 'gig') == 'rehearsal'
              ? ''
              : fmtDate(dateFrom.toString()));
      // Subject uses the customer's company name, not ours.
      final customerFirma =
          (widget.gig['customer_firma'] as String? ?? '').trim();
      final customerAndDate = [customerFirma, signedDates]
          .where((s) => s.isNotEmpty)
          .join(' ');
      final subjectLabel = [signedTitle, customerAndDate]
          .where((s) => s.isNotEmpty)
          .join(' — ');
      if (customerEmail.isNotEmpty) {
        final htmlBody = '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #1a1a1a; padding: 24px 32px; border-radius: 8px 8px 0 0;">
    <h1 style="color: white; font-size: 20px; margin: 0;">Signert intensjonsavtale</h1>
    <p style="color: #aaa; font-size: 14px; margin: 4px 0 0;">$subjectLabel</p>
  </div>
  <div style="background: #ffffff; padding: 28px 32px; border: 1px solid #eee; border-top: none; border-radius: 0 0 8px 8px;">
    <p style="font-size: 15px; line-height: 1.6; color: #333;">Hei $acceptedName,</p>
    <p style="font-size: 15px; line-height: 1.6; color: #333;">
      Intensjonsavtalen er nå godkjent av begge parter. Vedlagt finner du den signerte versjonen.
    </p>
    <p style="font-size: 13px; color: #888; margin-top: 20px;">Med vennlig hilsen,<br><strong>Complete Drums / Stian Skog</strong></p>
  </div>
</div>
''';
        await EmailService.sendEmailWithAttachments(
          to: customerEmail,
          subject: 'Signert — $subjectLabel',
          body: htmlBody,
          attachments: [
            (
              filename: _buildSignedFilename(signedResult, dateFrom.toString()),
              bytes: signedResult.mainPdf,
            ),
          ],
          isHtml: true,
          companyId: widget.gig['company_id'] as String?,
        );
      }

      await _loadAgreement();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avtale godkjent og signert kopi sendt!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Godkjenning feilet: $e')),
        );
      }
    }
    if (mounted) setState(() => _approving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final agreementStatus = _agreement?['status'] as String?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // -------- LIVE PDF VIEWER --------
        Expanded(
          child: _generating
              ? const Center(child: CircularProgressIndicator())
              : _pdfBytes == null
                  ? Center(
                      child: Text('Kunne ikke generere PDF',
                          style: TextStyle(color: cs.onSurfaceVariant)))
                  : PdfPreview(
                      key: ValueKey(_pdfBytes!.length),
                      build: (_) async => _pdfBytes!,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      allowPrinting: true,
                      allowSharing: true,
                      maxPageWidth: 750,
                    ),
        ),

        // -------- RIGHT SIDEBAR --------
        SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Intensjonsavtale',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_isMultiDate) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Felles kontrakt for ${widget.siblingGigs.length} datoer',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending
                      ? null
                      : () async {
                          setState(() => _sending = true);
                          await widget.onSend();
                          await _loadAgreement();
                          if (mounted) setState(() => _sending = false);
                        },
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(_sending ? 'Sender…' : 'Send intensjonsavtale'),
                ),
                if (_generating) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Regenererer PDF…',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],

                // -------- AGREEMENT STATUS --------
                if (_agreement != null) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Avtalestatus',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      IconButton(
                        tooltip: 'Oppdater status',
                        icon: _refreshingAgreement
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        onPressed: _refreshingAgreement
                            ? null
                            : () async {
                                setState(() => _refreshingAgreement = true);
                                await _loadAgreement();
                                if (mounted) {
                                  setState(
                                      () => _refreshingAgreement = false);
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Status badge
                  _AgreementStatusBadge(status: agreementStatus ?? 'pending'),
                  const SizedBox(height: 8),

                  // Send history (every send + recipients, newest first).
                  if (_sendHistory.isNotEmpty) ...[
                    Text(
                      'Sendinger',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    ..._sendHistory.map((s) {
                      final ts = DateTime.tryParse(
                          s['sent_at']?.toString() ?? '');
                      // Timestamps are timestamptz (UTC) — convert to the
                      // viewer's local time before formatting.
                      final tsLabel = ts != null
                          ? DateFormat('dd.MM.yyyy HH:mm').format(ts.toLocal())
                          : '';
                      final rcpts = (s['recipients'] as List?)
                              ?.map((e) => e.toString())
                              .where((e) => e.isNotEmpty)
                              .join(', ') ??
                          '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tsLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            if (rcpts.isNotEmpty)
                              Text(rcpts,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    // Fallback for tokens created before send-history existed
                    Text(
                      'Sendt til: ${_agreement!['customer_email'] ?? ''}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    if (_agreement!['created_at'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Sendt: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['created_at']).toLocal())}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],

                  // Accepted info
                  if (agreementStatus == 'accepted' || agreementStatus == 'approved') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Godtatt av: ${_agreement!['accepted_name'] ?? ''}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          if (_agreement!['accepted_at'] != null)
                            Text(
                              'Dato: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['accepted_at']).toLocal())}',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Approve button (only when accepted, not yet approved)
                  if (agreementStatus == 'accepted') ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _approving ? null : _approveAgreement,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      icon: Icon(_approving ? Icons.hourglass_top : Icons.check_circle, size: 18),
                      label: Text(_approving ? 'Godkjenner…' : 'Godkjenn og signer'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sender signert kopi til kunden',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],

                  // Approved info
                  if (agreementStatus == 'approved') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Avtale fullstendig signert',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blue),
                          ),
                          if (_agreement!['approved_at'] != null)
                            Text(
                              'Godkjent: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['approved_at']).toLocal())}',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Agreement status badge
// ---------------------------------------------------------------------------

/// Compact availability + counts card used on standalone rehearsals/other
/// (no full crew lineup tab). Mirrors the mobile app layout.
class _AvailabilitySummary extends StatelessWidget {
  final Map<String, dynamic> gig;
  final List<Map<String, dynamic>> companyMembers;
  final Future<void> Function(String status) onSetMyAvailability;

  const _AvailabilitySummary({
    required this.gig,
    required this.companyMembers,
    required this.onSetMyAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRehearsal = (gig['type'] as String? ?? 'gig') == 'rehearsal';
    final yesLabel = isRehearsal ? 'Skal' : 'Kan';
    final noLabel = isRehearsal ? 'Skal ikke' : 'Kan ikke';

    final availCount =
        companyMembers.where((m) => m['status'] == 'available').length;
    final unavailCount =
        companyMembers.where((m) => m['status'] == 'unavailable').length;
    final pendingCount =
        companyMembers.where((m) => m['status'] == 'pending').length;

    final myId = Supabase.instance.client.auth.currentUser?.id ?? '';
    Map<String, dynamic>? myMember;
    for (final m in companyMembers) {
      if (m['user_id'] == myId) {
        myMember = Map<String, dynamic>.from(m);
        break;
      }
    }
    final myStatus = (myMember?['status'] as String?) ?? 'pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myMember != null) ...[
            Text('Tilgjengelighet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AvailabilityButton(
                    label: yesLabel,
                    icon: Icons.check_circle,
                    color: Colors.green,
                    selected: myStatus == 'available',
                    onTap: () => onSetMyAvailability(
                        myStatus == 'available' ? 'pending' : 'available'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AvailabilityButton(
                    label: noLabel,
                    icon: Icons.cancel,
                    color: Colors.red,
                    selected: myStatus == 'unavailable',
                    onTap: () => onSetMyAvailability(myStatus == 'unavailable'
                        ? 'pending'
                        : 'unavailable'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text('Lag', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              _AvailCountBadge(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  label: '$availCount ${isRehearsal ? "skal" : "kan"}'),
              const SizedBox(width: 12),
              _AvailCountBadge(
                  icon: Icons.cancel,
                  color: Colors.red,
                  label:
                      '$unavailCount ${isRehearsal ? "skal ikke" : "kan ikke"}'),
              const SizedBox(width: 12),
              _AvailCountBadge(
                  icon: Icons.help_outline,
                  color: Colors.grey,
                  label: '$pendingCount ikke svart'),
            ],
          ),
          const SizedBox(height: 12),
          // Per-member list with status pills
          ...companyMembers.map((m) {
            final status = m['status'] as String? ?? 'pending';
            final color = status == 'available'
                ? Colors.green
                : status == 'unavailable'
                    ? Colors.red
                    : Colors.grey;
            final icon = status == 'available'
                ? Icons.check_circle
                : status == 'unavailable'
                    ? Icons.cancel
                    : Icons.help_outline;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m['name'] as String? ?? '',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AvailCountBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _AvailCountBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _AvailabilityButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AvailabilityButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: selected ? color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgreementStatusBadge extends StatelessWidget {
  final String status;
  const _AgreementStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      'pending' => (Colors.orange, 'Venter på svar'),
      'accepted' => (Colors.green, 'Godtatt av kunde'),
      'approved' => (Colors.blue, 'Signert'),
      _ => (Colors.grey, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ===========================================================================
// STATUS BADGE (reused from list page)
// ===========================================================================

class _GigStatusBadge extends StatelessWidget {
  final String status;
  const _GigStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'inquiry': Colors.orange,
      'confirmed': Colors.green,
      'cancelled': Colors.red,
      'invoiced': Colors.blue,
      'completed': Colors.grey,
    };
    const labels = {
      'inquiry': 'Forespørsel',
      'confirmed': 'Bekreftet',
      'cancelled': 'Avlyst',
      'invoiced': 'Fakturert',
      'completed': 'Fullført',
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        labels[status] ?? status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CHAT TAB
// ═══════════════════════════════════════════════════════════

class _ChatTab extends StatefulWidget {
  final String gigId;
  const _ChatTab({required this.gigId});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> with MentionMixin {
  final _sb = Supabase.instance.client;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _senderName = '';
  bool _sending = false;

  // Edit state
  String? _editingId;

  // Reply state
  Map<String, dynamic>? _replyTo;

  @override
  void initState() {
    super.initState();
    _loadSenderName();
    _msgCtrl.addListener(() => onMentionTextChanged(_msgCtrl));
    _loadMentionCandidates();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMentionCandidates() async {
    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId == null) return;
      final rows = await _sb.rpc(
        'get_company_member_profiles',
        params: {'p_company_id': companyId},
      );
      final myId = _sb.auth.currentUser?.id;
      final candidates = (rows as List)
          .where((r) => r['id'] != myId)
          .map((r) => MentionCandidate(
                id: r['id'] as String,
                name: r['name'] as String? ?? '',
              ))
          .where((c) => c.name.isNotEmpty)
          .toList();
      if (mounted) initMentionCandidates(candidates);
    } catch (_) {}
  }

  Future<String> _resolveSenderName() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'Admin';
    try {
      final p = await _sb
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      final profileName = (p?['name'] as String?)?.trim() ?? '';
      if (profileName.isNotEmpty) return profileName;
    } catch (_) {}
    final metaName =
        (user.userMetadata?['name'] as String?)?.trim() ?? '';
    if (metaName.isNotEmpty) return metaName;
    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) return email;
    return 'Admin';
  }

  Future<void> _loadSenderName() async {
    final name = await _resolveSenderName();
    if (mounted) setState(() => _senderName = name);
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);

    try {
      if (_editingId != null) {
        // Update existing message
        await _sb.from('gig_messages').update({
          'message': text,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _editingId!);
        _editingId = null;
      } else {
        // Resolve fresh — the cached name may not have loaded yet, or the
        // user just updated their profile elsewhere.
        final senderName =
            _senderName.isNotEmpty && _senderName != 'Admin'
                ? _senderName
                : await _resolveSenderName();
        if (mounted && senderName != _senderName) {
          setState(() => _senderName = senderName);
        }
        // Insert new message
        final mentions = List<String>.from(mentionedUserIds);
        final inserted = await _sb.from('gig_messages').insert({
          'gig_id': widget.gigId,
          'user_id': _sb.auth.currentUser!.id,
          'sender_name': senderName,
          'message': text,
          'is_admin': true,
          if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
          if (mentions.isNotEmpty) 'mentioned_user_ids': mentions,
        }).select('id').single();
        final newMessageId = inserted['id'] as String;
        clearMentions();

        // Notify
        try {
          final gig = await _sb
              .from('gigs')
              .select('company_id')
              .eq('id', widget.gigId)
              .maybeSingle();
          if (gig != null) {
            await _sb.functions.invoke('notify-chat', body: {
              'type': 'gig',
              'gig_id': widget.gigId,
              'company_id': gig['company_id'],
              'sender_id': _sb.auth.currentUser!.id,
              'sender_name': senderName,
              'message': text,
              'message_id': newMessageId,
            });
          }
        } catch (_) {}
      }

      _msgCtrl.clear();
      _replyTo = null;

      // Scroll to bottom after short delay
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startEdit(Map<String, dynamic> msg) {
    setState(() {
      _editingId = msg['id'] as String;
      _msgCtrl.text = msg['message'] as String;
      _replyTo = null;
    });
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() {
      _replyTo = msg;
      _editingId = null;
      _msgCtrl.clear();
    });
  }

  void _cancelEditReply() {
    setState(() {
      _editingId = null;
      _replyTo = null;
      _msgCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userId = _sb.auth.currentUser?.id;
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Column(
      children: [
        // Message list
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _sb
                .from('gig_messages')
                .stream(primaryKey: ['id'])
                .eq('gig_id', widget.gigId)
                .order('created_at', ascending: true),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final msgs = snap.data!;
              if (msgs.isEmpty) {
                return Center(
                  child: Text(
                    'Ingen meldinger ennå',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final msg = msgs[i];
                  final isAdmin = msg['is_admin'] == true;
                  final isOwn = msg['user_id'] == userId;
                  final edited = msg['edited_at'] != null;
                  final replyId = msg['reply_to_id'] as String?;

                  // Find reply-to message
                  Map<String, dynamic>? replyMsg;
                  if (replyId != null) {
                    replyMsg = msgs
                        .cast<Map<String, dynamic>?>()
                        .firstWhere((m) => m?['id'] == replyId,
                            orElse: () => null);
                  }

                  final bubbleColor =
                      isOwn ? Colors.black : const Color(0xFFEEEEEE);
                  final textColor = isOwn ? Colors.white : Colors.black87;
                  final align =
                      isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: align,
                      children: [
                        // Sender name
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            msg['sender_name'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ),
                        // Bubble
                        GestureDetector(
                          onSecondaryTapUp: isOwn
                              ? (details) => _showContextMenu(
                                    context, details.globalPosition, msg)
                              : (_) => _showReplyMenu(
                                    context, _.globalPosition, msg),
                          onLongPress: () {
                            if (isOwn) {
                              _startEdit(msg);
                            } else {
                              _startReply(msg);
                            }
                          },
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 500),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Reply quote
                                if (replyMsg != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: isOwn
                                          ? Colors.white.withOpacity(0.12)
                                          : Colors.black.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border(
                                        left: BorderSide(
                                          color: isOwn
                                              ? Colors.white54
                                              : Colors.black26,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${replyMsg['sender_name']}: ${(replyMsg['message'] as String).length > 60 ? '${(replyMsg['message'] as String).substring(0, 60)}…' : replyMsg['message']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isOwn
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                                // Message text — @mentions and URLs styled
                                Builder(builder: (_) {
                                  final base = TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                  );
                                  return SelectableText.rich(
                                    TextSpan(
                                      style: base,
                                      children: buildMentionSpans(
                                          (msg['message'] as String?) ?? '', base),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 2),
                                // Timestamp + edited
                                Text(
                                  '${df.format(DateTime.parse(msg['created_at']).toLocal())}${edited ? ' · redigert' : ''}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isOwn
                                        ? Colors.white60
                                        : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Edit / Reply indicator
        if (_editingId != null || _replyTo != null)
          Container(
            color: _editingId != null
                ? Colors.amber.withOpacity(0.15)
                : cs.primary.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _editingId != null ? Icons.edit : Icons.reply,
                  size: 16,
                  color: _editingId != null ? Colors.amber : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _editingId != null
                        ? 'Redigerer melding'
                        : 'Svarer ${_replyTo!['sender_name']}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _cancelEditReply,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        // Mention suggestions (shown while user types @name)
        MentionOverlay(
          suggestions: mentionSuggestions,
          onSelect: (c) => insertMention(_msgCtrl, c),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Skriv en melding…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _editingId != null ? Icons.check : Icons.send,
                        color: cs.primary,
                      ),
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, Map<String, dynamic> msg) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(value: 'reply', child: Text('Svar')),
        const PopupMenuItem(value: 'edit', child: Text('Rediger')),
      ],
    ).then((value) {
      if (value == 'edit') _startEdit(msg);
      if (value == 'reply') _startReply(msg);
    });
  }

  void _showReplyMenu(
      BuildContext context, Offset position, Map<String, dynamic> msg) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(value: 'reply', child: Text('Svar')),
      ],
    ).then((value) {
      if (value == 'reply') _startReply(msg);
    });
  }
}
