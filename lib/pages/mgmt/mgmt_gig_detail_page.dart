import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';
import '../../state/active_company.dart';
import '../../services/intensjonsavtale_pdf_service.dart';
import '../../services/email_service.dart';

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
  List<Map<String, dynamic>> _lineup = [];
  Set<String> _selectedSkarp = {};
  Set<String> _selectedBass = {};


  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
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

      // Adjust tab count: rehearsal only needs Info tab
      final isRehearsal = (gig?['type'] as String?) == 'rehearsal';
      final desiredLength = isRehearsal ? 1 : 2;
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

        final avail = await _sb
            .from('gig_availability')
            .select('user_id, status')
            .eq('gig_id', widget.gigId);
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

        // Load lineup
        final lineupData = await _sb
            .from('gig_lineup')
            .select('user_id, section')
            .eq('gig_id', widget.gigId);
        _lineup = List<Map<String, dynamic>>.from(lineupData);
        _selectedSkarp = {};
        _selectedBass = {};
        for (final l in _lineup) {
          if (l['section'] == 'skarp') {
            _selectedSkarp.add(l['user_id'] as String);
          } else if (l['section'] == 'bass') {
            _selectedBass.add(l['user_id'] as String);
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
    } catch (e) {
      debugPrint('Gig detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------------
  // LINEUP HELPERS
  // -------------------------------------------------------------------------

  void _toggleLineupMember(String userId, String section) {
    setState(() {
      final set = section == 'skarp' ? _selectedSkarp : _selectedBass;
      if (set.contains(userId)) {
        set.remove(userId);
      } else {
        set.add(userId);
      }
    });
  }

  Future<void> _saveLineup(String section) async {
    final selected = section == 'skarp' ? _selectedSkarp : _selectedBass;
    // Delete existing lineup for this section
    await _sb
        .from('gig_lineup')
        .delete()
        .eq('gig_id', widget.gigId)
        .eq('section', section);
    // Insert new
    if (selected.isNotEmpty) {
      await _sb.from('gig_lineup').insert(
        selected
            .map((uid) => {
                  'gig_id': widget.gigId,
                  'user_id': uid,
                  'section': section,
                })
            .toList(),
      );
    }
  }

  Future<void> _saveAndToggleLock(String section) async {
    try {
      // Save lineup first
      await _saveLineup(section);
      // Toggle lock
      final field = section == 'skarp'
          ? 'lineup_locked_skarp'
          : 'lineup_locked_bass';
      final currentlyLocked = _gig?[field] == true;
      await _sb
          .from('gigs')
          .update({field: !currentlyLocked})
          .eq('id', widget.gigId);
      await _load();
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
                          TextField(
                            controller: notesCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dette skal vi gjøre på øvelsen',
                              isDense: true,
                            ),
                            maxLines: 3,
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
              const Text(
                  'PDF-avtalen blir generert og sendt til mottakeren under.'),
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
              Uint8List? bytes;
              try {
                bytes = await IntensjonsavtalePdfService.generate(
                  gig: _gig!,
                  shows: _shows,
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
                final venue = _gig?['venue_name'] ?? 'gig';
                final dateFrom = _gig?['date_from'] ?? '';
                await EmailService.sendEmailWithAttachment(
                  to: emailCtrl.text.trim(),
                  subject: 'Intensjonsavtale — $venue $dateFrom',
                  body:
                      'Hei,\n\nVedlagt finner du intensjonsavtalen for oppdrag ${venue != '' ? 'ved $venue' : ''} ${dateFrom != '' ? 'den $dateFrom' : ''}.\n\nMed vennlig hilsen,\nComplete Drums / Stian Skog',
                  attachmentBytes: bytes,
                  attachmentFilename:
                      'Intensjonsavtale_${venue.replaceAll(' ', '_')}.pdf',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Intensjonsavtale sendt!')),
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, size: 13, color: CssTheme.textMuted),
                SizedBox(width: 2),
                Text(
                  'Gigs',
                  style: TextStyle(
                    color: CssTheme.textMuted,
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
                              color: CssTheme.textMuted,
                            ),
                      ),
                    if (gigType == 'rehearsal' && title.isNotEmpty)
                      Text(
                        title,
                        style: const TextStyle(
                          color: CssTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    if (customerLine.isNotEmpty && gigType != 'rehearsal')
                      Text(
                        customerLine,
                        style: const TextStyle(
                          color: CssTheme.textMuted,
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
              if (gigType == 'rehearsal' && status != 'cancelled') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Øvelse',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple),
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
            tabs: _gig?['type'] == 'rehearsal'
                ? const [Tab(text: 'Info')]
                : const [
                    Tab(text: 'Info'),
                    Tab(text: 'Kontrakt'),
                  ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: _gig?['type'] == 'rehearsal'
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
                            ),
                            const SizedBox(height: 12),
                            _CrewLineupTab(
                              companyMembers: _companyMembers,
                              gig: _gig!,
                              selectedSkarp: _selectedSkarp,
                              selectedBass: _selectedBass,
                              onToggleMember: _toggleLineupMember,
                              onSaveAndLock: _saveAndToggleLock,
                            ),
                          ],
                        ),
                      ),
                      _KontraktTab(
                        gig: _gig!,
                        shows: _shows,
                        total: _total,
                        onSend: _sendIntensjon,
                      ),
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
                _card('Sted', [
                  MapEntry('Venue', gig['venue_name']),
                  MapEntry('By', gig['city']),
                  MapEntry('Land', gig['country']),
                ]),
                _card('Tider', [
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
                  _card('Ansvarlig', [
                    MapEntry('Navn', gig['responsible']),
                  ]),
                _card('Notat', [
                  MapEntry('Dette skal vi gjøre', gig['notes_for_contract']),
                ]),
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
              _card('Sted', [
                MapEntry('Venue', gig['venue_name']),
                MapEntry('By', gig['city']),
                MapEntry('Land', gig['country']),
              ]),
              _card('Kunde', [
                MapEntry('Firma', gig['customer_firma']),
                MapEntry('Kontakt', gig['customer_name']),
                MapEntry('Telefon', gig['customer_phone']),
                MapEntry('E-post', gig['customer_email']),
                MapEntry('Org.nr', gig['customer_org_nr']),
                MapEntry('Adresse', gig['customer_address']),
                MapEntry('EHF', gig['invoice_on_ehf'] == true ? 'Ja' : null),
              ]),
              _card('Tider', [
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
              _card('Scene', [
                MapEntry('Form', gig['stage_shape']),
                MapEntry('Størrelse', gig['stage_size']),
                MapEntry('Notat', gig['stage_notes']),
              ]),
              _card('Teknikk', [
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
              _card('Transport & Extra', [
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
              _card('Notater', [
                MapEntry('For kontrakt', gig['notes_for_contract']),
                MapEntry('Fra arrangør', gig['info_from_organizer']),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(String title, List<MapEntry<String, dynamic>> entries) {
    final nonEmpty = entries
        .where((e) => e.value?.toString().isNotEmpty ?? false)
        .toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CssTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: CssTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...nonEmpty.map((e) => _InfoRow(label: e.key, value: e.value?.toString())),
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

  const _InfoRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(
                color: CssTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
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
  });

  @override
  State<_ShowsPrisTab> createState() => _ShowsPrisTabState();
}

class _ShowsPrisTabState extends State<_ShowsPrisTab> {
  final _nok = NumberFormat('#,##0', 'nb_NO');

  String _fmt(double v) => 'kr ${_nok.format(v)}';

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Shows',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
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
            const Text('Ingen shows lagt til ennå.',
                style: TextStyle(color: CssTheme.textMuted))
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: CssTheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: CssTheme.surface2,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12)),
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
              color: CssTheme.surface,
              border: Border.all(color: CssTheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prisoppsummering',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
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
    final show = widget.show;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : const Border(
                bottom: BorderSide(color: CssTheme.outline)),
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
  final Set<String> selectedSkarp;
  final Set<String> selectedBass;
  final void Function(String userId, String section) onToggleMember;
  final Future<void> Function(String section) onSaveAndLock;

  const _CrewLineupTab({
    required this.companyMembers,
    required this.gig,
    required this.selectedSkarp,
    required this.selectedBass,
    required this.onToggleMember,
    required this.onSaveAndLock,
  });

  @override
  Widget build(BuildContext context) {
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
          const Text('Ingen medlemmer lagt til ennå.',
              style: TextStyle(color: CssTheme.textMuted))
        else ...[
          // Skarp section
          _buildSectionBlock(
            context,
            title: 'Skarp',
            color: Colors.purple,
            members: skarpMembers,
            selected: selectedSkarp,
            section: 'skarp',
            locked: lockedSkarp,
          ),
          const SizedBox(height: 16),

          // Bass section
          _buildSectionBlock(
            context,
            title: 'Bass',
            color: Colors.teal,
            members: bassMembers,
            selected: selectedBass,
            section: 'bass',
            locked: lockedBass,
          ),

          // No section
          if (noSectionMembers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionBlock(
              context,
              title: 'Ingen seksjon',
              color: Colors.grey,
              members: noSectionMembers,
              selected: const {},
              section: '',
              locked: false,
              readOnly: true,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionBlock(
    BuildContext context, {
    required String title,
    required Color color,
    required List<Map<String, dynamic>> members,
    required Set<String> selected,
    required String section,
    required bool locked,
    bool readOnly = false,
  }) {
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
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const Spacer(),
            if (!readOnly && section.isNotEmpty)
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
              style: TextStyle(color: CssTheme.textMuted, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: CssTheme.outline),
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
                        : const Border(
                            bottom: BorderSide(color: CssTheme.outline)),
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
                              : (_) => onToggleMember(uid, section),
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

  const _KontraktTab({
    required this.gig,
    required this.shows,
    required this.total,
    required this.onSend,
  });

  @override
  State<_KontraktTab> createState() => _KontraktTabState();
}

class _KontraktTabState extends State<_KontraktTab> {
  Uint8List? _pdfBytes;
  bool _generating = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _buildPdf();
  }

  @override
  void didUpdateWidget(_KontraktTab old) {
    super.didUpdateWidget(old);
    if (old.gig != widget.gig || old.shows != widget.shows) {
      _buildPdf();
    }
  }

  Future<void> _buildPdf() async {
    if (mounted) setState(() => _generating = true);
    try {
      final bytes = await IntensjonsavtalePdfService.generate(
        gig: widget.gig,
        shows: widget.shows,
      );
      if (mounted) setState(() => _pdfBytes = bytes);
    } catch (e) {
      debugPrint('PDF build error: $e');
    }
    if (mounted) setState(() => _generating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // -------- LIVE PDF VIEWER --------
        Expanded(
          child: _generating
              ? const Center(child: CircularProgressIndicator())
              : _pdfBytes == null
                  ? const Center(
                      child: Text('Kunne ikke generere PDF',
                          style: TextStyle(color: CssTheme.textMuted)))
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
          width: 220,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Intensjonsavtale',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending
                      ? null
                      : () async {
                          setState(() => _sending = true);
                          await widget.onSend();
                          if (mounted) setState(() => _sending = false);
                        },
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(_sending ? 'Sender…' : 'Send intensjonsavtale'),
                ),
                if (_generating) ...[
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Regenererer PDF…',
                          style: TextStyle(
                              fontSize: 11, color: CssTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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
