import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
import '../../services/intensjonsavtale_pdf_service.dart';
import '../../services/email_service.dart';
import '../../widgets/rich_text_field.dart';

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
  Map<String, dynamic>? _offerData; // the linked offer (for final_calc etc.)
  List<Map<String, dynamic>> _lineup = [];
  // showId → Set<userId> per section
  Map<String, Set<String>> _selectedSkarpByShow = {};
  Map<String, Set<String>> _selectedBassByShow = {};


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

      // Adjust tab count: only gigs get full tabs
      final isGig = (gig?['type'] as String?) == 'gig';
      final desiredLength = isGig ? 3 : 1;
      if (_tabCtrl.length != desiredLength) {
        _tabCtrl.dispose();
        _tabCtrl = TabController(length: desiredLength, vsync: this);
      }

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

      // Fetch team members from profiles (same source as Settings)
      final companyId = _gig?['company_id'] as String? ??
          activeCompanyNotifier.value?.id;
      if (companyId != null) {
        final members = await _sb
            .from('profiles')
            .select('id, name, role, section')
            .eq('company_id', companyId);

        // Auto-set all members to "available" for rehearsals
        final isRehearsal = (_gig?['type'] as String?) == 'rehearsal';
        if (isRehearsal) {
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
      if (_linkedOfferId != null) {
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
              .select('id, date_from, date_to, venue_name, city, country')
              .inFilter('id', siblingIds)
              .order('date_from', ascending: true);
          _siblingGigs = List<Map<String, dynamic>>.from(siblings);
          // Load the offer for final_calc and pricing params
          _offerData = await _sb
              .from('gig_offers')
              .select('*')
              .eq('id', _linkedOfferId!)
              .maybeSingle();
        }
      }
    } catch (e) {
      debugPrint('Gig detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------------
  // LINEUP HELPERS
  // -------------------------------------------------------------------------

  void _toggleLineupMember(String userId, String section, String showId) {
    setState(() {
      final map = section == 'skarp'
          ? _selectedSkarpByShow
          : _selectedBassByShow;
      map.putIfAbsent(showId, () => {});
      final set = map[showId]!;
      if (set.contains(userId)) {
        set.remove(userId);
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
    // Insert new — one row per (user, show)
    final rows = <Map<String, dynamic>>[];
    for (final entry in map.entries) {
      final showId = entry.key;
      for (final uid in entry.value) {
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
      // Only save lineup when locking, not when unlocking
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

  double get _showsTotal =>
      _shows.fold(0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));

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
                Row(
                  children: [
                    Expanded(child: _tf(drumCtrl, 'Trommeslagere',
                        keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _tf(danceCtrl, 'Dansere',
                        keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _tf(othersCtrl, 'Andre',
                        keyboardType: TextInputType.number)),
                  ],
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

  Future<void> _updateShowPrice(String showId, double price) async {
    try {
      await _sb.from('gig_shows').update({'price': price}).eq('id', showId);
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

    // Sum show prices across all sibling gigs' gig_shows
    // We only have _shows for this gig, but shows are typically the same across dates
    final showPricePerGig = _shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    final inearTotal = inearIncluded ? inearPrice * numDates : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    final totalTransport = (transportPrice * numDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final rehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
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
  List<({String date, String venue})> get _pdfDateEntriesFromDetail {
    final df = DateFormat('dd.MM.yyyy');
    return _siblingGigs.map((g) {
      final dateFrom = g['date_from'] as String?;
      final dateStr = dateFrom != null ? df.format(DateTime.parse(dateFrom)) : '';
      final venue = [
        g['venue_name'] as String? ?? '',
        g['city'] as String? ?? '',
        g['country'] as String? ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
      return (date: dateStr, venue: venue);
    }).toList();
  }

  Future<void> _sendIntensjon() async {
    final emailCtrl =
        TextEditingController(text: _gig?['customer_email'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Intensjonsavtale'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isMultiDate
                  ? 'PDF-avtalen for alle ${_siblingGigs.length} datoer blir generert og sendt med aksepteringslenke.'
                  : 'PDF-avtalen blir generert og sendt med aksepteringslenke.'),
              const SizedBox(height: 12),
              _tf(emailCtrl, 'Mottaker e-post'),
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
              ({Uint8List mainPdf, List<({String filename, Uint8List bytes})> riders})? result;
              try {
                final calc = _isMultiDate ? _offerCalcFromDetail : null;
                result = await IntensjonsavtalePdfService.generate(
                  gig: _gig!,
                  shows: _shows,
                  calcLines: calc?.lines,
                  calcTotal: calc?.total,
                  dateEntries: _isMultiDate ? _pdfDateEntriesFromDetail : null,
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
                final toEmail = emailCtrl.text.trim();

                // 1. Create agreement token (on canonical gig)
                final tokenRow = await _sb.from('agreement_tokens').insert({
                  'gig_id': canonicalGigId,
                  'customer_email': toEmail,
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
                final subjectLabel = _isMultiDate
                    ? '${_siblingGigs.length} datoer'
                    : '$venue $dateFrom';
                final venueLabel = venue != '' ? 'ved $venue' : '';
                final dateLabel = dateFrom != '' ? 'den $dateFrom' : '';
                final bodyDesc = _isMultiDate
                    ? 'for ${_siblingGigs.length} avtalte datoer'
                    : 'for oppdrag $venueLabel $dateLabel';
                final htmlBody = '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #1a1a1a; padding: 24px 32px; border-radius: 8px 8px 0 0;">
    <h1 style="color: white; font-size: 20px; margin: 0;">Intensjonsavtale</h1>
    <p style="color: #aaa; font-size: 14px; margin: 4px 0 0;">$subjectLabel</p>
  </div>
  <div style="background: #ffffff; padding: 28px 32px; border: 1px solid #eee; border-top: none;">
    <p style="font-size: 15px; line-height: 1.6; color: #333;">Hei,</p>
    <p style="font-size: 15px; line-height: 1.6; color: #333;">
      Vedlagt finner du intensjonsavtalen $bodyDesc.
    </p>
    <p style="font-size: 15px; line-height: 1.6; color: #333;">
      Du kan lese gjennom avtalen i vedlegget, og deretter godta den ved å trykke på knappen under:
    </p>
    <div style="text-align: center; margin: 28px 0;">
      <a href="$acceptUrl" style="display: inline-block; padding: 14px 36px; background: #16a34a; color: white; text-decoration: none; border-radius: 8px; font-size: 16px; font-weight: 600;">
        Aksepter avtale
      </a>
    </div>
    <p style="font-size: 13px; color: #888; line-height: 1.5;">
      Ved å akseptere bekrefter du at du har lest og godtar betingelsene i intensjonsavtalen.
    </p>
  </div>
  <div style="padding: 16px 32px; background: #f9f9f9; border: 1px solid #eee; border-top: none; border-radius: 0 0 8px 8px;">
    <p style="font-size: 13px; color: #666; margin: 0;">Med vennlig hilsen,<br><strong>Complete Drums / Stian Skog</strong></p>
  </div>
</div>
''';

                final attachments = <({String filename, Uint8List bytes})>[
                  (filename: 'Intensjonsavtale_${venue.toString().replaceAll(' ', '_')}.pdf', bytes: result.mainPdf),
                  ...result.riders,
                ];
                await EmailService.sendEmailWithAttachments(
                  to: toEmail,
                  subject: 'Intensjonsavtale — $subjectLabel',
                  body: htmlBody,
                  attachments: attachments,
                  isHtml: true,
                  companyId: _gig?['company_id'] as String?,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Intensjonsavtale sendt med aksepteringslenke!')),
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
                  'Gigs',
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
                          ? 'Øvelse'
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
                    if (gigType == 'rehearsal' && title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    if (customerLine.isNotEmpty && gigType != 'rehearsal')
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
              if (gigType != 'rehearsal' && status != 'cancelled')
                _GigStatusBadge(status: status),
              if (gigType != 'rehearsal') ...[
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'edit') {
                    if (gigType == 'rehearsal') {
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
                        Text(gigType == 'rehearsal' ? 'Rediger øvelse' : 'Rediger'),
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
                          gigType == 'rehearsal' ? 'Slett øvelse' : 'Slett gig',
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

          // Tabs — rehearsal only shows Info tab
          TabBar(
            controller: _tabCtrl,
            tabs: _gig?['type'] != 'gig'
                ? const [Tab(text: 'Info')]
                : const [
                    Tab(text: 'Info'),
                    Tab(text: 'Kontrakt'),
                    Tab(text: 'Chat'),
                  ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: _gig?['type'] != 'gig'
                  ? [
                      SingleChildScrollView(
                        child: _InfoTab(gig: _gig!),
                      ),
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
                            _InfoTab(gig: _gig!),
                            const SizedBox(height: 12),
                            _ShowsPrisTab(
                              gig: _gig!,
                              shows: _shows,
                              showTypes: _showTypes,
                              onAddShow: _addShow,
                              onDeleteShow: _deleteShow,
                              onUpdatePrice: _updateShowPrice,
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

class _InfoTab extends StatelessWidget {
  final Map<String, dynamic> gig;

  const _InfoTab({required this.gig});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gigType = gig['type'] as String? ?? 'gig';
    final isGig = gigType == 'gig';

    if (!isGig) {
      // Rehearsal layout
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _card(cs, 'Sted', [
                  MapEntry('Venue', gig['venue_name']),
                  MapEntry('By', gig['city']),
                  MapEntry('Land', gig['country']),
                ]),
                _card(cs, 'Tider', [
                  MapEntry('Fra', gig['meeting_time']),
                  MapEntry('Til', gig['get_out_time']),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                if (gig['responsible'] != null)
                  _card(cs, 'Ansvarlig', [
                    MapEntry('Navn', gig['responsible']),
                  ]),
                _card(cs, 'Notat', [
                  MapEntry('Dette skal vi gjøre', gig['notes_for_contract']),
                ], useMarkdown: true),
              ],
            ),
          ),
        ],
      );
    }

    // Gig layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column
        Expanded(
          child: Column(
            children: [
              _card(cs, 'Sted', [
                MapEntry('Venue', gig['venue_name']),
                MapEntry('By', gig['city']),
                MapEntry('Land', gig['country']),
              ]),
              _card(cs, 'Kunde', [
                MapEntry('Firma', gig['customer_firma']),
                MapEntry('Kontakt', gig['customer_name']),
                MapEntry('Telefon', gig['customer_phone']),
                MapEntry('E-post', gig['customer_email']),
                MapEntry('Org.nr', gig['customer_org_nr']),
                MapEntry('Adresse', gig['customer_address']),
                MapEntry('EHF', gig['invoice_on_ehf'] == true ? 'Ja' : null),
              ]),
              _card(cs, 'Tider', [
                MapEntry('Oppmøte', gig['meeting_time']),
                MapEntry('Get-in', gig['get_in_time']),
                MapEntry('Prøver', gig['rehearsal_time']),
                MapEntry('Opptreden', gig['performance_time']),
                MapEntry('Get-out', gig['get_out_time']),
                MapEntry('Notat', gig['meeting_notes']),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right column
        Expanded(
          child: Column(
            children: [
              _card(cs, 'Scene', [
                MapEntry('Form', gig['stage_shape']),
                MapEntry('Størrelse', gig['stage_size']),
                MapEntry('Notat', gig['stage_notes']),
              ]),
              _card(cs, 'Teknikk', [
                MapEntry('In-ear fra oss',
                    gig['inear_from_us'] == true ? 'Ja' : 'Nei'),
                MapEntry(
                    'In-ear pris',
                    gig['inear_from_us'] == true
                        ? 'kr ${_fmt(gig['inear_price'])}'
                        : null),
                MapEntry('Playback fra oss',
                    gig['playback_from_us'] != false ? 'Ja' : 'Nei'),
              ]),
              _card(cs, 'Transport & Extra', [
                MapEntry('Km', gig['transport_km']?.toString()),
                MapEntry(
                    'Transport',
                    gig['transport_price'] != null
                        ? 'kr ${_fmt(gig['transport_price'])}'
                        : null),
                MapEntry('Extra', gig['extra_desc']),
                MapEntry(
                    'Extra pris',
                    gig['extra_price'] != null
                        ? 'kr ${_fmt(gig['extra_price'])}'
                        : null),
              ]),
              _card(cs, 'Notater', [
                MapEntry('For kontrakt', gig['notes_for_contract']),
                MapEntry('Fra arrangør', gig['info_from_organizer']),
              ], useMarkdown: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(ColorScheme cs, String title, List<MapEntry<String, dynamic>> entries, {bool useMarkdown = false}) {
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
          ...nonEmpty.map((e) => _InfoRow(label: e.key, value: e.value?.toString(), useMarkdown: useMarkdown)),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    final n = (v as num).toDouble();
    return NumberFormat('#,##0', 'nb_NO').format(n);
  }
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

              return ActionChip(
                label: Text(label, style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                )),
                backgroundColor: isCurrent ? cs.primary : cs.surfaceContainerHigh,
                side: BorderSide.none,
                onPressed: isCurrent ? null : () => context.go('/m/gigs/$gId'),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
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
      final lines = rawLines.map<({String label, double amount})>((l) {
        return (
          label: l['label'] as String? ?? '',
          amount: (l['amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      // Merge CompleteKonto + BookingHonorar into Utøverhyrer
      double ck = 0, bh = 0;
      for (final l in lines) {
        if (l.label == 'CompleteKonto') ck = l.amount;
        if (l.label == 'BookingHonorar') bh = l.amount;
      }
      final merged = lines
          .map((l) => l.label == 'Utøverhyrer'
              ? (label: l.label, amount: l.amount + ck + bh)
              : l)
          .where((l) =>
              l.amount > 0 &&
              l.label != 'CompleteKonto' &&
              l.label != 'BookingHonorar')
          .toList();
      final total = (fc['total'] as num?)?.toDouble() ?? 0;
      return (lines: merged, total: total);
    }
    // Fallback: compute from offer params
    return _computeFromOffer();
  }

  ({List<({String label, double amount})> lines, double total})? _computeFromOffer() {
    if (widget.offerData == null) return null;
    final o = widget.offerData!;
    final numDates = widget.siblingGigs.length;

    final showPricePerGig = widget.shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    final inearTotal = inearIncluded ? inearPrice * numDates : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    final totalTransport = (transportPrice * numDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final rehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
    final rehearsalPPP = (o['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0;
    final rehearsalTotal = (rehearsalPerformers * rehearsalCount * rehearsalPPP).toDouble();

    final markupPct = (o['markup_pct'] as num?)?.toDouble() ?? 0;
    final markupOnAll = o['markup_on_all'] == true;
    final completePct = markupPct / 2;
    final bookingPct = markupPct / 2;

    final subtotal = performerFees + inearTotal + totalTransport + rehearsalTotal;
    final markupBase = markupOnAll ? subtotal : performerFees;
    // Merge markup into performer fees for display
    final displayPerformerFees = performerFees + (markupBase * completePct) + (markupBase * bookingPct);

    final ovJson = o['calc_overrides'];
    final ov = <String, double>{};
    if (ovJson is Map) {
      for (final e in ovJson.entries) {
        if (e.value is num) ov[e.key as String] = (e.value as num).toDouble();
      }
    }
    // If overrides exist for individual lines, use them but still merge markup
    final pfOv = ov['performer_fees'];
    final ckOv = ov['complete_konto'];
    final bhOv = ov['booking_honorar'];
    final finalPF = (pfOv ?? performerFees) + (ckOv ?? markupBase * completePct) + (bhOv ?? markupBase * bookingPct);

    double ovv(String key, double calc) => ov.containsKey(key) ? ov[key]! : calc;

    final lines = <({String label, double amount})>[
      (label: 'Utøverhyrer', amount: ov.containsKey('performer_fees') || ov.containsKey('complete_konto') || ov.containsKey('booking_honorar') ? finalPF : displayPerformerFees),
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
                    child: Row(
                      children: const [
                        Expanded(
                            flex: 3,
                            child: Text('Show',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12))),
                        SizedBox(
                            width: 70,
                            child: Text('Trommer',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 70,
                            child: Text('Dansere',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 70,
                            child: Text('Andre',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 110,
                            child: Text('Pris',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                                textAlign: TextAlign.right)),
                        SizedBox(width: 40),
                      ],
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
                if (_isMultiDate && _offerCalcLines != null) ...[
                  ..._offerCalcLines!.lines.map((l) =>
                      _PriceRow(label: l.label, value: _fmt(l.amount))),
                  const Divider(height: 20),
                  _PriceRow(
                    label: 'TILBUD (${widget.siblingGigs.length} datoer)',
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
  final VoidCallback onDelete;
  final Future<void> Function(double) onUpdatePrice;

  const _ShowRow({
    required this.show,
    required this.isLast,
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
    _priceCtrl = TextEditingController(
        text: widget.show['price']?.toString() ?? '0');
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
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (v) async {
                      final p = double.tryParse(v) ?? 0;
                      await widget.onUpdatePrice(p);
                      setState(() => _editing = false);
                    },
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editing = true),
                    child: Text(
                      'kr ${NumberFormat('#,##0', 'nb_NO').format((show['price'] as num?)?.toDouble() ?? 0)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
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

  const _CrewLineupTab({
    required this.companyMembers,
    required this.gig,
    required this.shows,
    required this.selectedSkarpByShow,
    required this.selectedBassByShow,
    required this.onToggleMember,
    required this.onSaveAndLock,
    required this.onCopyToAllShows,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lag', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        Row(
          children: [
            _availBadge(Icons.check_circle, Colors.green,
                '$availCount kan'),
            const SizedBox(width: 12),
            _availBadge(Icons.cancel, Colors.red,
                '$unavailCount kan ikke'),
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
    final selectedCount = selected.length;
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
                '$title ($selectedCount valgt)',
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
                        child: Text(
                          (m['name'] as String?) ?? 'Ukjent',
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
  final String? linkedOfferId;

  const _KontraktTab({
    required this.gig,
    required this.shows,
    required this.total,
    required this.onSend,
    this.siblingGigs = const [],
    this.offerData,
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

  @override
  void initState() {
    super.initState();
    _buildPdf();
    _loadAgreement();
  }

  @override
  void didUpdateWidget(_KontraktTab old) {
    super.didUpdateWidget(old);
    if (old.gig != widget.gig || old.shows != widget.shows) {
      _buildPdf();
    }
  }

  bool get _isMultiDate => widget.siblingGigs.length > 1;

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

    final showPricePerGig = widget.shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final performerFees = showPricePerGig * numDates;

    final inearIncluded = o['inear_included'] == true;
    final inearPrice = (o['inear_price'] as num?)?.toDouble() ?? 0;
    final inearTotal = inearIncluded ? inearPrice * numDates : 0.0;

    final transportPrice = (o['transport_price'] as num?)?.toDouble() ?? 0;
    final rehearsalTransport = (o['rehearsal_transport'] as num?)?.toDouble() ?? 0;
    final totalTransport = (transportPrice * numDates) + rehearsalTransport;

    final rehearsalPerformers = (o['rehearsal_performers'] as num?)?.toInt() ?? 0;
    final rehearsalCount = (o['rehearsal_count'] as num?)?.toInt() ?? 0;
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

  /// Build date entries for multi-date PDF
  List<({String date, String venue})> get _pdfDateEntries {
    final df = DateFormat('dd.MM.yyyy');
    return widget.siblingGigs.map((g) {
      final dateFrom = g['date_from'] as String?;
      final dateStr = dateFrom != null ? df.format(DateTime.parse(dateFrom)) : '';
      final venue = [
        g['venue_name'] as String? ?? '',
        g['city'] as String? ?? '',
        g['country'] as String? ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
      return (date: dateStr, venue: venue);
    }).toList();
  }

  Future<void> _buildPdf() async {
    if (mounted) setState(() => _generating = true);
    try {
      final calc = _isMultiDate ? _offerCalc : null;
      final result = await IntensjonsavtalePdfService.generate(
        gig: widget.gig,
        shows: widget.shows,
        calcLines: calc?.lines,
        calcTotal: calc?.total,
        dateEntries: _isMultiDate ? _pdfDateEntries : null,
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

      final row = await _sb
          .from('agreement_tokens')
          .select()
          .inFilter('gig_id', gigIds)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _agreement = row);
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
      final acceptedDate = acceptedAt != null
          ? DateFormat('dd.MM.yyyy').format(DateTime.parse(acceptedAt))
          : DateFormat('dd.MM.yyyy').format(DateTime.now());
      final approvedDate = DateFormat('dd.MM.yyyy').format(DateTime.now());

      final calc = _isMultiDate ? _offerCalc : null;
      final signedResult = await IntensjonsavtalePdfService.generate(
        gig: widget.gig,
        shows: widget.shows,
        customerSignature: acceptedName,
        customerSignatureDate: acceptedDate,
        companySignature: 'Stian Skog',
        companySignatureDate: approvedDate,
        calcLines: calc?.lines,
        calcTotal: calc?.total,
        dateEntries: _isMultiDate ? _pdfDateEntries : null,
      );

      // Send signed PDF to customer
      final customerEmail = _agreement!['customer_email'] as String? ?? '';
      final venue = widget.gig['venue_name'] ?? '';
      final dateFrom = widget.gig['date_from'] ?? '';
      final subjectLabel = _isMultiDate
          ? '${widget.siblingGigs.length} datoer'
          : '$venue $dateFrom';
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
          subject: 'Signert intensjonsavtale — $subjectLabel',
          body: htmlBody,
          attachments: [
            (filename: 'Signert_Intensjonsavtale_${venue.toString().replaceAll(' ', '_')}.pdf', bytes: signedResult.mainPdf),
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
                  Text('Avtalestatus',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),

                  // Status badge
                  _AgreementStatusBadge(status: agreementStatus ?? 'pending'),
                  const SizedBox(height: 8),

                  // Sent to
                  Text(
                    'Sendt til: ${_agreement!['customer_email'] ?? ''}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (_agreement!['created_at'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Sendt: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['created_at']))}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
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
                              'Dato: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['accepted_at']))}',
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
                              'Godkjent: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(_agreement!['approved_at']))}',
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

class _ChatTabState extends State<_ChatTab> {
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
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSenderName() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final p = await _sb
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _senderName = (p?['name'] ?? '').toString().trim().isNotEmpty
              ? p!['name'] as String
              : user.email ?? 'Admin';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _senderName = user.email ?? 'Admin');
    }
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
        // Insert new message
        await _sb.from('gig_messages').insert({
          'gig_id': widget.gigId,
          'user_id': _sb.auth.currentUser!.id,
          'sender_name': _senderName,
          'message': text,
          'is_admin': true,
          if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
        });

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
              'sender_name': _senderName,
              'message': text,
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
    final df = DateFormat('dd.MM HH:mm');

    return Column(
      children: [
        // Message list
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _sb
                .from('gig_messages')
                .stream(primaryKey: ['id'])
                .eq('gig_id', widget.gigId)
                .order('created_at'),
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

                  final bubbleColor = isAdmin
                      ? cs.primary.withOpacity(0.12)
                      : cs.surfaceContainerHighest;
                  final align =
                      isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start;

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
                                      color: cs.onSurface.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border(
                                        left: BorderSide(
                                          color: cs.primary,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${replyMsg['sender_name']}: ${(replyMsg['message'] as String).length > 60 ? '${(replyMsg['message'] as String).substring(0, 60)}…' : replyMsg['message']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                ],
                                // Message text
                                SelectableText(
                                  msg['message'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Timestamp + edited
                                Text(
                                  '${df.format(DateTime.parse(msg['created_at']).toLocal())}${edited ? ' · redigert' : ''}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withOpacity(0.35),
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
