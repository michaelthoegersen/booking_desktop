import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/brreg_service.dart';
import '../../state/active_company.dart';
import '../../state/settings_store.dart';
import '../../ui/css_theme.dart';
import '../../widgets/new_company_dialog.dart';
import '../../widgets/rich_text_field.dart';

class MgmtGigsPage extends StatefulWidget {
  const MgmtGigsPage({super.key});

  @override
  State<MgmtGigsPage> createState() => _MgmtGigsPageState();
}

class _MgmtGigsPageState extends State<MgmtGigsPage> {
  final _sb = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? get _companyId => activeCompanyNotifier.value?.id;
  List<Map<String, dynamic>> _gigs = [];
  String _search = '';
  String _statusFilter = 'all';
  String _typeFilter = 'all'; // 'all', 'gig', 'rehearsal'

  // Multi-select for bus booking
  bool _selectionMode = false;
  final Set<String> _selectedGigIds = {};

  static const _statuses = ['all', 'upcoming', 'confirmed', 'invoiced'];

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onCompanyChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_companyId == null) {
        setState(() => _loading = false);
        return;
      }

      final gigs = await _sb
          .from('gigs')
          .select('*, gig_shows(show_name)')
          .eq('company_id', _companyId!)
          .eq('archived', false)
          .order('date_from', ascending: true);

      _gigs = List<Map<String, dynamic>>.from(gigs);
    } catch (e) {
      debugPrint('Gigs load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _gigs;

    if (_typeFilter != 'all') {
      list = list
          .where((g) => (g['type'] as String? ?? 'gig') == _typeFilter)
          .toList();
    }

    if (_statusFilter != 'all') {
      if (_statusFilter == 'upcoming') {
        final today = DateTime.now();
        list = list.where((g) {
          final d = g['date_from'] as String?;
          if (d == null) return false;
          return DateTime.parse(d).isAfter(today);
        }).toList();
      } else {
        list = list.where((g) => g['status'] == _statusFilter).toList();
      }
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((g) {
        final venue = (g['venue_name'] as String? ?? '').toLowerCase();
        final city = (g['city'] as String? ?? '').toLowerCase();
        final firma = (g['customer_firma'] as String? ?? '').toLowerCase();
        final name = (g['customer_name'] as String? ?? '').toLowerCase();
        return venue.contains(q) ||
            city.contains(q) ||
            firma.contains(q) ||
            name.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _openNewGigDialog() async {
    if (_companyId == null) return;

    // Ask user what type to create
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ny aktivitet'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'gig'),
            child: const Row(children: [
              Icon(Icons.music_note, size: 20),
              SizedBox(width: 12),
              Text('Gig', style: TextStyle(fontSize: 15)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'rehearsal'),
            child: const Row(children: [
              Icon(Icons.piano, size: 20),
              SizedBox(width: 12),
              Text('Øvelse', style: TextStyle(fontSize: 15)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'meeting'),
            child: const Row(children: [
              Icon(Icons.groups, size: 20),
              SizedBox(width: 12),
              Text('Møte', style: TextStyle(fontSize: 15)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'other'),
            child: const Row(children: [
              Icon(Icons.event, size: 20),
              SizedBox(width: 12),
              Text('Annet', style: TextStyle(fontSize: 15)),
            ]),
          ),
        ],
      ),
    );

    if (type == null || !mounted) return;

    if (type == 'gig') {
      // Gig → open the offer page (creates both gig + gig_offer)
      context.go('/m/offers/new');
    } else if (type == 'meeting') {
      // Møte → open the meeting wizard
      context.go('/m/meetings/new');
    } else {
      // Øvelse/Annet → open the dialog with type locked
      final gigId = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewGigDialog(
          managementCompanyId: _companyId!,
          forceType: type,
        ),
      );

      if (gigId != null && mounted) {
        context.go('/m/gigs/$gigId');
      } else {
        await _load();
      }
    }
  }

  Future<void> _confirmCancel(Map<String, dynamic> gig) async {
    final venue = gig['venue_name'] as String?;
    final dateFrom = gig['date_from'] as String?;
    final label = venue?.isNotEmpty == true ? venue! : (dateFrom ?? 'denne gigen');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avlys aktivitet'),
        content: Text('Er du sikker på at du vil avlyse "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Avlys'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _sb
          .from('gigs')
          .update({'status': 'cancelled'})
          .eq('id', gig['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke avlyse: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> gig) async {
    final venue = gig['venue_name'] as String?;
    final dateFrom = gig['date_from'] as String?;
    final label = venue?.isNotEmpty == true ? venue! : (dateFrom ?? 'denne gigen');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett gig'),
        content: Text(
          'Er du sikker på at du vil slette "$label"?\n\n'
          'Alle shows og crew tilknyttet gigen vil også slettes.',
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
      await _sb.from('gigs').delete().eq('id', gig['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

  void _toggleGigSelection(String gigId) {
    setState(() {
      if (_selectedGigIds.contains(gigId)) {
        _selectedGigIds.remove(gigId);
        if (_selectedGigIds.isEmpty) _selectionMode = false;
      } else {
        _selectedGigIds.add(gigId);
      }
    });
  }

  Future<void> _openBookNightlinerDialog() async {
    if (_selectedGigIds.isEmpty || _companyId == null) return;
    final cs = Theme.of(context).colorScheme;

    // Sort selected gigs by date
    final selectedGigs = _gigs
        .where((g) => _selectedGigIds.contains(g['id'] as String))
        .where((g) => (g['type'] as String? ?? 'gig') != 'rehearsal')
        .toList()
      ..sort((a, b) {
        final da = a['date_from'] as String? ?? '';
        final db = b['date_from'] as String? ?? '';
        return da.compareTo(db);
      });

    if (selectedGigs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen gyldige gigs valgt (øvelser ekskludert)')),
      );
      return;
    }

    final fromCityCtrl = TextEditingController();
    final toCityCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final paxCtrl = TextEditingController();
    bool trailer = false;
    int busCount = 1;

    // Build route preview
    String buildRoutePreview(String from, String to) {
      final stops = selectedGigs
          .map((g) => g['city'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
      final parts = <String>[
        if (from.isNotEmpty) from,
        ...stops,
        if (to.isNotEmpty) to,
      ];
      return parts.join(' → ');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Book Nightliner (${selectedGigs.length} gig${selectedGigs.length > 1 ? 's' : ''})'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selected gigs summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: selectedGigs.map((g) {
                      final venue = g['venue_name'] as String? ?? '';
                      final city = g['city'] as String? ?? '';
                      final dateFrom = g['date_from'] as String?;
                      final label = [venue, city].where((s) => s.isNotEmpty).join(' · ');
                      final dateLabel = dateFrom != null
                          ? DateFormat('dd.MM.yyyy').format(DateTime.parse(dateFrom))
                          : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '$dateLabel — $label',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fromCityCtrl,
                        decoration: const InputDecoration(labelText: 'Fra by'),
                        onChanged: (_) => setS(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: toCityCtrl,
                        decoration: const InputDecoration(labelText: 'Til by'),
                        onChanged: (_) => setS(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Route preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.route, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          buildRoutePreview(fromCityCtrl.text.trim(), toCityCtrl.text.trim()),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<int>(
                        value: busCount,
                        decoration: const InputDecoration(labelText: 'Busser'),
                        items: List.generate(4, (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}'),
                        )),
                        onChanged: (v) {
                          if (v != null) setS(() => busCount = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: paxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Passasjerer',
                          suffixText: 'pax',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: trailer,
                  onChanged: (v) => setS(() => trailer = v ?? false),
                  title: const Text('Trailer'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notater'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send, size: 16),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Send forespørsel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // Compute overall date range across all selected gigs
      final allDatesFrom = selectedGigs
          .map((g) => g['date_from'] as String?)
          .whereType<String>()
          .toList()..sort();
      final allDatesTo = selectedGigs
          .map((g) => (g['date_to'] as String?) ?? (g['date_from'] as String?))
          .whereType<String>()
          .toList()..sort();

      final overallFrom = allDatesFrom.isNotEmpty ? allDatesFrom.first : null;
      final overallTo = allDatesTo.isNotEmpty ? allDatesTo.last : overallFrom;

      // Insert ONE bus_request for the whole route
      final inserted = await _sb.from('bus_requests').insert({
        'company_id': _companyId,
        'date_from': overallFrom,
        'date_to': overallTo,
        'from_city': fromCityCtrl.text.trim(),
        'to_city': toCityCtrl.text.trim(),
        'pax': int.tryParse(paxCtrl.text.trim()),
        'trailer': trailer,
        'bus_count': busCount,
        'notes': notesCtrl.text.trim(),
        'status': 'pending',
      }).select('id').single();

      final busRequestId = inserted['id'] as String;

      // Link all gigs via junction table
      for (int i = 0; i < selectedGigs.length; i++) {
        await _sb.from('bus_request_gigs').insert({
          'bus_request_id': busRequestId,
          'gig_id': selectedGigs[i]['id'],
          'sort_order': i,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nightliner-forespørsel sendt: ${buildRoutePreview(fromCityCtrl.text.trim(), toCityCtrl.text.trim())}',
            ),
          ),
        );
        setState(() {
          _selectionMode = false;
          _selectedGigIds.clear();
        });
      }
    } catch (e) {
      debugPrint('Bus request error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Future<void> _showCalendarDialog() async {
    if (_companyId == null) return;
    final cs = Theme.of(context).colorScheme;

    // Check if calendar_token already exists
    final company = await _sb
        .from('companies')
        .select('calendar_token')
        .eq('id', _companyId!)
        .maybeSingle();

    String? token = company?['calendar_token'] as String?;

    // Generate token if missing
    if (token == null || token.isEmpty) {
      final rng = Random.secure();
      token = List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _sb
          .from('companies')
          .update({'calendar_token': token})
          .eq('id', _companyId!);
    }

    final calUrl =
        'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/gig-calendar'
        '?company_id=$_companyId&token=$token';
    final webcalUrl = calUrl.replaceFirst('https://', 'webcal://');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kalender-abonnement'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Abonner på gig-kalenderen i din kalender-app. '
                'Kalenderen oppdateres automatisk når gigs endres.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  calUrl,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopier URL'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: calUrl));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('URL kopiert til utklippstavle')),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Åpne i kalender'),
                    onPressed: () {
                      launchUrl(Uri.parse(webcalUrl));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Lukk'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Aktiviteter',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Søk i aktiviteter…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              if (Supabase.instance.client.auth.currentUser?.email == 'michael@nttas.com')
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selectedGigIds.clear();
                    });
                  },
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.directions_bus,
                    size: 18,
                  ),
                  label: Text(_selectionMode ? 'Avbryt' : 'Book Nightliner'),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _showCalendarDialog,
                icon: const Icon(Icons.calendar_month),
                tooltip: 'Kalender-abonnement',
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _openNewGigDialog,
                icon: const Icon(Icons.add),
                label: const Text('Ny aktivitet'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Filters row — type + status as compact text tabs
          Row(
            children: [
              // Type filters
              ...const [
                ('all', 'Alle'),
                ('gig', 'Gigs'),
                ('rehearsal', 'Øvelser'),
                ('meeting', 'Møter'),
                ('other', 'Annet'),
              ].map((e) {
                final active = _typeFilter == e.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: InkWell(
                    onTap: () => setState(() => _typeFilter = e.$1),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        e.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
                          decoration: active ? TextDecoration.underline : TextDecoration.none,
                          decorationThickness: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Divider
              Container(
                height: 20,
                width: 1,
                color: cs.outlineVariant,
                margin: const EdgeInsets.only(right: 16),
              ),

              // Status filters
              ..._statuses.map((s) {
                final active = _statusFilter == s;
                final label = const {
                  'all': 'Alle',
                  'upcoming': 'Kommende',
                  'confirmed': 'Bekreftet',
                  'invoiced': 'Fakturert',
                }[s] ?? _capitalize(s);
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: InkWell(
                    onTap: () => setState(() => _statusFilter = s),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
                          decoration: active ? TextDecoration.underline : TextDecoration.none,
                          decorationThickness: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),

          const SizedBox(height: 14),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _search.isNotEmpty || _statusFilter != 'all' || _typeFilter != 'all'
                              ? 'Ingen aktiviteter matcher filteret'
                              : 'Ingen aktiviteter ennå. Opprett din første aktivitet!',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : Column(
                        children: [
                          if (_selectionMode && _selectedGigIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Text(
                                    '${_selectedGigIds.length} gig(s) valgt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: _openBookNightlinerDialog,
                                    icon: const Icon(Icons.send, size: 16),
                                    label: const Text('Send forespørsel'),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) {
                                final gig = _filtered[i];
                                final gigId = gig['id'] as String;
                                final isGig = (gig['type'] as String? ?? 'gig') == 'gig';
                                return _GigRow(
                                  gig: gig,
                                  onTap: _selectionMode && isGig
                                      ? () => _toggleGigSelection(gigId)
                                      : () => context.go('/m/gigs/$gigId'),
                                  onCancel: () => _confirmCancel(gig),
                                  onDelete: () => _confirmDelete(gig),
                                  selectionMode: _selectionMode,
                                  selected: _selectedGigIds.contains(gigId),
                                  onSelect: isGig ? () => _toggleGigSelection(gigId) : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ===========================================================================
// NEW GIG DIALOG
// ===========================================================================

class _NewGigDialog extends StatefulWidget {
  final String managementCompanyId;
  final String? forceType;

  const _NewGigDialog({required this.managementCompanyId, this.forceType});

  @override
  State<_NewGigDialog> createState() => _NewGigDialogState();
}

class _NewGigDialogState extends State<_NewGigDialog> {
  final _sb = Supabase.instance.client;

  // ── Companies / contacts ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;
  List<Map<String, dynamic>> _contacts = [];
  Map<String, dynamic>? _selectedContact;
  bool _loadingCompanies = true;

  // ── Type ──────────────────────────────────────────────────────────────────
  String _type = 'gig';

  // ── Date / status ─────────────────────────────────────────────────────────
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _status = 'inquiry';

  // ── Booleans ──────────────────────────────────────────────────────────────
  bool _invoiceOnEhf = false;
  bool _inearFromUs = false;
  bool _playbackFromUs = true;

  // ── Text controllers ──────────────────────────────────────────────────────
  final _venueCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'NO');
  final _firmaCtrl = TextEditingController();
  final _custNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _orgNrCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _responsibleCtrl = TextEditingController();
  final _showDescCtrl = TextEditingController();
  final _meetingTimeCtrl = TextEditingController();
  final _getInTimeCtrl = TextEditingController();
  final _rehearsalTimeCtrl = TextEditingController();
  final _performanceTimeCtrl = TextEditingController();
  final _getOutTimeCtrl = TextEditingController();
  final _meetingNotesCtrl = TextEditingController();
  final _stageShapeCtrl = TextEditingController();
  final _stageSizeCtrl = TextEditingController();
  final _stageNotesCtrl = TextEditingController();
  final _inearPriceCtrl = TextEditingController(
      text: SettingsStore.current.inearPrice.toStringAsFixed(0));
  final _transportKmCtrl = TextEditingController();
  final _transportPriceCtrl = TextEditingController();
  final _extraDescCtrl = TextEditingController();
  final _extraPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _infoFromOrgCtrl = TextEditingController();

  bool _saving = false;

  // ── Show types ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _showTypes = [];
  Map<String, dynamic>? _selectedShow;
  final _showPriceCtrl = TextEditingController();
  final _drumCtrl = TextEditingController();
  final _danceCtrl = TextEditingController();
  final _othersCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.forceType != null) _type = widget.forceType!;
    _loadCompanies();
    _loadShowTypes();
  }

  @override
  void dispose() {
    for (final c in [
      _venueCtrl, _cityCtrl, _countryCtrl, _firmaCtrl, _custNameCtrl,
      _phoneCtrl, _emailCtrl, _orgNrCtrl, _addressCtrl, _responsibleCtrl,
      _showDescCtrl, _meetingTimeCtrl, _getInTimeCtrl, _rehearsalTimeCtrl,
      _performanceTimeCtrl, _getOutTimeCtrl, _meetingNotesCtrl,
      _stageShapeCtrl, _stageSizeCtrl, _stageNotesCtrl, _inearPriceCtrl,
      _transportKmCtrl, _transportPriceCtrl, _extraDescCtrl, _extraPriceCtrl,
      _notesCtrl, _infoFromOrgCtrl,
      _showPriceCtrl, _drumCtrl, _danceCtrl, _othersCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Load companies ─────────────────────────────────────────────────────────

  Future<void> _loadCompanies({String? autoSelectId}) async {
    try {
      final res = await _sb
          .from('companies')
          .select('id, name, org_nr, address, city, country, contacts!contacts_company_id_fkey(id, name, phone, email)')
          .eq('owner_company_id', widget.managementCompanyId)
          .order('name');
      final list = List<Map<String, dynamic>>.from(res);
      setState(() {
        _companies = list;
        _loadingCompanies = false;
      });
      if (autoSelectId != null) {
        final match = list.where((c) => c['id'] == autoSelectId).firstOrNull;
        if (match != null) _applyCompany(match);
      }
    } catch (e) {
      debugPrint('Load companies error: $e');
      if (mounted) setState(() => _loadingCompanies = false);
    }
  }

  Future<void> _loadShowTypes() async {
    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId == null) return;
      final res = await _sb
          .from('show_types')
          .select('*')
          .eq('company_id', companyId)
          .eq('active', true)
          .order('sort_order');
      if (mounted) setState(() {
        _showTypes = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Load show types error: $e');
    }
  }

  // ── Apply company to fields ────────────────────────────────────────────────

  void _applyCompany(Map<String, dynamic> company) {
    final contacts = (company['contacts'] as List<dynamic>? ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();

    setState(() {
      _selectedCompany = company;
      _contacts = contacts;
      _firmaCtrl.text = company['name'] as String? ?? '';
      _orgNrCtrl.text = company['org_nr'] as String? ?? '';
      _addressCtrl.text = company['address'] as String? ?? '';
      if (contacts.isNotEmpty) {
        _selectedContact = contacts.first;
        _custNameCtrl.text = contacts.first['name'] as String? ?? '';
        _phoneCtrl.text = contacts.first['phone'] as String? ?? '';
        _emailCtrl.text = contacts.first['email'] as String? ?? '';
      } else {
        _selectedContact = null;
        _custNameCtrl.clear();
        _phoneCtrl.clear();
        _emailCtrl.clear();
      }
    });

    // Reload companies list if this is a newly created company (e.g. from Brreg)
    final id = company['id'] as String?;
    if (id != null && !_companies.any((c) => c['id'] == id)) {
      _loadCompanies();
    }
  }

  void _clearCompany() {
    setState(() {
      _selectedCompany = null;
      _contacts = [];
      _selectedContact = null;
      _firmaCtrl.clear();
      _orgNrCtrl.clear();
      _addressCtrl.clear();
      _custNameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
    });
  }

  void _applyContact(Map<String, dynamic> contact) {
    setState(() {
      _selectedContact = contact;
      _custNameCtrl.text = contact['name'] as String? ?? '';
      _phoneCtrl.text = contact['phone'] as String? ?? '';
      _emailCtrl.text = contact['email'] as String? ?? '';
    });
  }

  // ── Open new company dialog ────────────────────────────────────────────────

  Future<void> _openNewCompany() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewCompanyDialog(
        ownerCompanyId: widget.managementCompanyId,
      ),
    );
    if (result != null) {
      await _loadCompanies(autoSelectId: result);
    }
  }

  // ── Save gig ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_dateFrom == null) return;
    setState(() => _saving = true);
    try {
      final df = DateFormat('yyyy-MM-dd');
      String? n(String s) => s.trim().isEmpty ? null : s.trim();

      final res = await _sb.from('gigs').insert({
        'company_id': widget.managementCompanyId,
        'type': _type,
        'date_from': df.format(_dateFrom!),
        if (_dateTo != null) 'date_to': df.format(_dateTo!),
        'status': _status,
        'venue_name': n(_venueCtrl.text),
        'city': n(_cityCtrl.text),
        'country': n(_countryCtrl.text),
        'customer_firma': n(_firmaCtrl.text),
        'customer_name': n(_custNameCtrl.text),
        'customer_phone': n(_phoneCtrl.text),
        'customer_email': n(_emailCtrl.text),
        'customer_org_nr': n(_orgNrCtrl.text),
        'customer_address': n(_addressCtrl.text),
        'invoice_on_ehf': _invoiceOnEhf,
        'responsible': n(_responsibleCtrl.text),
        'show_desc': n(_showDescCtrl.text),
        'meeting_time': n(_meetingTimeCtrl.text),
        'get_in_time': n(_getInTimeCtrl.text),
        'rehearsal_time': n(_rehearsalTimeCtrl.text),
        'performance_time': n(_performanceTimeCtrl.text),
        'get_out_time': n(_getOutTimeCtrl.text),
        'meeting_notes': n(_meetingNotesCtrl.text),
        'stage_shape': n(_stageShapeCtrl.text),
        'stage_size': n(_stageSizeCtrl.text),
        'stage_notes': n(_stageNotesCtrl.text),
        'inear_from_us': _inearFromUs,
        'playback_from_us': _playbackFromUs,
        'inear_price': double.tryParse(_inearPriceCtrl.text) ?? SettingsStore.current.inearPrice,
        'transport_km': int.tryParse(_transportKmCtrl.text),
        'transport_price': double.tryParse(_transportPriceCtrl.text),
        'extra_desc': n(_extraDescCtrl.text),
        'extra_price': double.tryParse(_extraPriceCtrl.text),
        'notes_for_contract': n(_notesCtrl.text),
        'info_from_organizer': n(_infoFromOrgCtrl.text),
        'created_by': _sb.auth.currentUser?.id,
      }).select('id').single();

      final gigId = res['id'] as String;

      // Insert show if selected
      if (_selectedShow != null) {
        await _sb.from('gig_shows').insert({
          'gig_id': gigId,
          'show_type_id': _selectedShow!['id'],
          'show_name': _selectedShow!['name'],
          'drummers': int.tryParse(_drumCtrl.text) ?? 0,
          'dancers': int.tryParse(_danceCtrl.text) ?? 0,
          'others': int.tryParse(_othersCtrl.text) ?? 0,
          'price': double.tryParse(_showPriceCtrl.text) ?? 0,
          'sort_order': 0,
        });
      }

      // Notify crew about the new gig
      try {
        final venue = n(_venueCtrl.text) ?? '';
        final date = df.format(_dateFrom!);
        final label = const {'gig': 'Ny gig', 'rehearsal': 'Ny øvelse', 'meeting': 'Nytt møte', 'other': 'Ny aktivitet'}[_type] ?? 'Ny aktivitet';
        await _sb.functions.invoke('notify-company', body: {
          'company_id': widget.managementCompanyId,
          'title': '$label: $venue',
          'body': '$date — $venue',
          'exclude_user_id': _sb.auth.currentUser?.id,
          'gig_id': gigId,
        });
      } catch (_) {}

      if (mounted) Navigator.of(context).pop(gigId);
    } catch (e) {
      debugPrint('Create gig error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 660,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                const {'gig': 'Ny Gig', 'rehearsal': 'Ny Øvelse', 'meeting': 'Nytt Møte', 'other': 'Ny Aktivitet'}[_type] ?? 'Ny Aktivitet',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),

              // Type toggle (hidden when type is forced)
              if (widget.forceType == null) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gig', label: Text('Gig'), icon: Icon(Icons.music_note, size: 16)),
                    ButtonSegment(value: 'rehearsal', label: Text('Øvelse'), icon: Icon(Icons.piano, size: 16)),
                    ButtonSegment(value: 'meeting', label: Text('Møte'), icon: Icon(Icons.groups, size: 16)),
                    ButtonSegment(value: 'other', label: Text('Annet'), icon: Icon(Icons.event, size: 16)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() => _type = v.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 16),
              ],

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── DATES + STATUS ──────────────────────────────────
                      _sec('Dato'),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_dateFrom != null
                                  ? df.format(_dateFrom!)
                                  : 'Dato fra *'),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _dateFrom ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (d != null) setState(() => _dateFrom = d);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_dateTo != null
                                  ? df.format(_dateTo!)
                                  : 'Dato til'),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _dateFrom ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (d != null) setState(() => _dateTo = d);
                              },
                            ),
                          ),
                          if (_type == 'gig') ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _status,
                              decoration: const InputDecoration(
                                  labelText: 'Status', isDense: true),
                              items: ['inquiry', 'confirmed', 'invoiced',
                                      'completed', 'cancelled']
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(const {
                                          'inquiry': 'Forespørsel',
                                          'confirmed': 'Bekreftet',
                                          'invoiced': 'Fakturert',
                                          'completed': 'Fullført',
                                          'cancelled': 'Avlyst',
                                        }[s] ?? s),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _status = v ?? _status),
                            ),
                          ),
                          ],
                        ],
                      ),

                      // ── LOCATION ────────────────────────────────────────
                      _sec('Spillested'),
                      _row([
                        _tf(_venueCtrl, 'Spillested', flex: 2),
                        _tf(_cityCtrl, 'By'),
                        _tf(_countryCtrl, 'Land', flex: 0, width: 80),
                      ]),
                      const SizedBox(height: 8),
                      _tfFull(_responsibleCtrl, 'Ansvarlig'),

                      // ── CUSTOMER (gig only) ─────────────────────────────
                      if (_type == 'gig') ...[
                      _sec('Kunde'),
                      _CustomerPicker(
                        companies: _companies,
                        selectedCompany: _selectedCompany,
                        loading: _loadingCompanies,
                        onSelected: _applyCompany,
                        onClear: _clearCompany,
                        onNewCompany: _openNewCompany,
                        ownerCompanyId: widget.managementCompanyId,
                      ),
                      if (_contacts.length > 1) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedContact,
                          decoration: const InputDecoration(
                              labelText: 'Velg kontaktperson'),
                          items: _contacts
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c['name'] as String? ?? ''),
                                  ))
                              .toList(),
                          onChanged: (c) {
                            if (c != null) _applyContact(c);
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      _row([
                        _tf(_firmaCtrl, 'Firma'),
                        _tf(_orgNrCtrl, 'Org.nr'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_custNameCtrl, 'Kontaktperson'),
                        _tf(_phoneCtrl, 'Telefon'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_emailCtrl, 'E-post'),
                        _tf(_addressCtrl, 'Adresse'),
                      ]),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        title: const Text('Faktura på EHF'),
                        value: _invoiceOnEhf,
                        onChanged: (v) =>
                            setState(() => _invoiceOnEhf = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),

                      // ── SHOW (gig only) ─────────────────────────────────
                      _sec('Show'),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(labelText: 'Velg show'),
                        value: _selectedShow,
                        items: _showTypes
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t['name'] as String),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedShow = v;
                            if (v != null) {
                              _showPriceCtrl.text = v['price']?.toString() ?? '0';
                              _drumCtrl.text = v['drummers']?.toString() ?? '0';
                              _danceCtrl.text = v['dancers']?.toString() ?? '0';
                              _othersCtrl.text = v['others']?.toString() ?? '0';
                            }
                          });
                        },
                      ),
                      if (_selectedShow != null) ...[
                        const SizedBox(height: 8),
                        _row([
                          _tf(_drumCtrl, 'Trommeslagere',
                              keyboardType: TextInputType.number),
                          _tf(_danceCtrl, 'Dansere',
                              keyboardType: TextInputType.number),
                          _tf(_othersCtrl, 'Andre',
                              keyboardType: TextInputType.number),
                        ]),
                        const SizedBox(height: 8),
                        _tfFull(_showPriceCtrl, 'Pris (kr)',
                            keyboardType: TextInputType.number),
                      ],
                      const SizedBox(height: 8),
                      _tfFull(_showDescCtrl, 'Beskriv showet (valgfritt)', maxLines: 2),
                      ], // end if gig

                      // ── SCHEDULE ────────────────────────────────────────
                      if (_type != 'gig') ...[
                      _sec('Timeplan'),
                      _row([
                        _tf(_meetingTimeCtrl, 'Fra'),
                        _tf(_getOutTimeCtrl, 'Til'),
                      ]),
                      ],

                      if (_type == 'gig') ...[
                      _sec('Timeplan'),
                      _row([
                        _tf(_meetingTimeCtrl, 'Oppmøte'),
                        _tf(_getInTimeCtrl, 'Get-in'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_rehearsalTimeCtrl, 'Prøver'),
                        _tf(_performanceTimeCtrl, 'Opptreden'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_getOutTimeCtrl, 'Get-out'),
                        const Spacer(),
                      ]),
                      const SizedBox(height: 8),
                      _tfFull(_meetingNotesCtrl, 'Oppmøtenotat',
                          maxLines: 2),

                      // ── STAGE ───────────────────────────────────────────
                      _sec('Scene'),
                      _row([
                        _tf(_stageShapeCtrl, 'Sceneform'),
                        _tf(_stageSizeCtrl, 'Scenestørrelse'),
                      ]),
                      const SizedBox(height: 8),
                      _tfFull(_stageNotesCtrl, 'Scenenoter', maxLines: 2),
                      ],

                      // ── TECH (gig only) ─────────────────────────────────
                      if (_type == 'gig') ...[
                      _sec('Teknikk'),
                      SwitchListTile(
                        title: const Text('In-ear fra oss'),
                        value: _inearFromUs,
                        onChanged: (v) =>
                            setState(() => _inearFromUs = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      if (_inearFromUs) ...[
                        _tfFull(_inearPriceCtrl, 'In-ear pris (kr)',
                            keyboardType: TextInputType.number),
                        const SizedBox(height: 8),
                      ],
                      SwitchListTile(
                        title: const Text('Playback fra oss'),
                        value: _playbackFromUs,
                        onChanged: (v) =>
                            setState(() => _playbackFromUs = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),

                      // ── TRANSPORT ───────────────────────────────────────
                      _sec('Transport'),
                      _row([
                        _tf(_transportKmCtrl, 'Km',
                            keyboardType: TextInputType.number),
                        _tf(_transportPriceCtrl, 'Pris (kr)',
                            keyboardType: TextInputType.number),
                      ]),

                      // ── EXTRA ───────────────────────────────────────────
                      _sec('Ekstra'),
                      _row([
                        _tf(_extraDescCtrl, 'Beskrivelse', flex: 2),
                        _tf(_extraPriceCtrl, 'Pris (kr)',
                            keyboardType: TextInputType.number),
                      ]),

                      // ── NOTES (gig only) ────────────────────────────────
                      _sec('Notat'),
                      RichTextField(
                        controller: _notesCtrl,
                        label: 'Notat for kontrakt',
                        minLines: 2,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 8),
                      RichTextField(
                        controller: _infoFromOrgCtrl,
                        label: 'Info fra arrangør',
                        minLines: 2,
                        maxLines: 5,
                      ),
                      ], // end if gig

                      // ── REHEARSAL NOTES ─────────────────────────────────
                      if (_type != 'gig') ...[
                      _sec('Notat'),
                      RichTextField(
                        controller: _notesCtrl,
                        label: 'Notat / hva skal gjøres',
                        minLines: 3,
                        maxLines: 6,
                      ),
                      ],

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: const Text('Avbryt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_saving || _dateFrom == null)
                          ? null
                          : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(const {'gig': 'Opprett gig', 'rehearsal': 'Opprett øvelse', 'meeting': 'Opprett møte', 'other': 'Opprett aktivitet'}[_type] ?? 'Opprett'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget _sec(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: cs.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );
  }

  static Widget _tf(
    TextEditingController ctrl,
    String label, {
    int flex = 1,
    double? width,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final field = TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(labelText: label),
    );
    if (width != null) return SizedBox(width: width, child: field);
    return Expanded(flex: flex, child: field);
  }

  static Widget _tfFull(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(labelText: label),
    );
  }

  static Widget _row(List<Widget> children) {
    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) spaced.add(const SizedBox(width: 8));
    }
    return Row(children: spaced);
  }
}

// ===========================================================================
// CUSTOMER PICKER
// Uses a modal AlertDialog picker instead of Autocomplete+Overlay to avoid
// RenderBox layout errors inside scrollable Dialogs.
// ===========================================================================

class _CustomerPicker extends StatelessWidget {
  final List<Map<String, dynamic>> companies;
  final Map<String, dynamic>? selectedCompany;
  final bool loading;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final VoidCallback onClear;
  final VoidCallback onNewCompany;
  final String? ownerCompanyId;

  const _CustomerPicker({
    required this.companies,
    required this.selectedCompany,
    required this.loading,
    required this.onSelected,
    required this.onClear,
    required this.onNewCompany,
    this.ownerCompanyId,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomerPickerDialog(
        companies: companies,
        ownerCompanyId: ownerCompanyId,
      ),
    );
    if (result != null) onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = selectedCompany;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: loading ? null : () => _openPicker(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: loading
                    ? Colors.black.withValues(alpha: 0.04)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 18,
                    color: loading
                        ? cs.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: loading
                        ? Text('Laster kunder…',
                            style: TextStyle(color: cs.onSurfaceVariant))
                        : selected != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    selected['name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  if ((selected['city'] as String?) != null)
                                    Text(
                                      selected['city'] as String,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant),
                                    ),
                                ],
                              )
                            : Text(
                                'Velg kunde…',
                                style:
                                    TextStyle(color: cs.onSurfaceVariant),
                              ),
                  ),
                  if (selected != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Fjern kunde',
                      onPressed: onClear,
                    )
                  else
                    Icon(Icons.arrow_drop_down,
                        color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Ny kunde',
          child: FilledButton.tonalIcon(
            onPressed: loading ? null : onNewCompany,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ny kunde'),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Modal picker dialog — no Overlay, safe inside any Dialog
// ---------------------------------------------------------------------------

class _CustomerPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> companies;
  final String? ownerCompanyId;

  const _CustomerPickerDialog({
    required this.companies,
    this.ownerCompanyId,
  });

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Brreg
  final _brregCtrl = TextEditingController();
  Timer? _brregDebounce;
  List<BrregCompany> _brregResults = [];
  bool _brregSearching = false;
  bool _brregCreating = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _brregCtrl.dispose();
    _brregDebounce?.cancel();
    super.dispose();
  }

  void _onBrregSearch(String query) {
    _brregDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _brregResults = []);
      return;
    }
    _brregDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _brregSearching = true);
      try {
        final cleaned = query.replaceAll(RegExp(r'\s'), '');
        if (RegExp(r'^\d{9}$').hasMatch(cleaned)) {
          final result = await BrregService.lookup(cleaned);
          if (mounted) {
            setState(() {
              _brregResults = result != null ? [result] : [];
              _brregSearching = false;
            });
          }
        } else {
          final results = await BrregService.search(query);
          if (mounted) {
            setState(() {
              _brregResults = results;
              _brregSearching = false;
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _brregSearching = false);
      }
    });
  }

  Future<void> _selectBrreg(BrregCompany c) async {
    setState(() => _brregCreating = true);
    try {
      final sb = Supabase.instance.client;
      final inserted = await sb.from('companies').insert({
        'name': c.name,
        'org_nr': c.orgNr,
        'address': c.address,
        'postal_code': c.postalCode,
        'city': c.city,
        'country': c.country,
        if (widget.ownerCompanyId != null)
          'owner_company_id': widget.ownerCompanyId,
      }).select().single();

      if (mounted) Navigator.pop(context, inserted);
    } catch (e) {
      debugPrint('Brreg create company error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette: $e')),
        );
        setState(() => _brregCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _query.isEmpty
        ? widget.companies
        : widget.companies.where((c) {
            final name = (c['name'] as String? ?? '').toLowerCase();
            final city = (c['city'] as String? ?? '').toLowerCase();
            final orgNr = (c['org_nr'] as String? ?? '').toLowerCase();
            final q = _query.toLowerCase();
            return name.contains(q) || city.contains(q) || orgNr.contains(q);
          }).toList();

    return AlertDialog(
      title: const Text('Velg kunde'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: 'Eksisterende'),
                Tab(text: 'Søk i Brreg'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── Tab 1: existing companies ──
                  Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Søk på navn eller by…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text('Ingen treff',
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant)))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) {
                                  final c = filtered[i];
                                  final name =
                                      c['name'] as String? ?? '';
                                  final city = c['city'] as String?;
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                        Icons.business_outlined,
                                        size: 18),
                                    title: Text(name,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w700)),
                                    subtitle: city != null
                                        ? Text(city,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: CssTheme
                                                    .textMuted))
                                        : null,
                                    onTap: () =>
                                        Navigator.pop(ctx, c),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // ── Tab 2: Brreg search ──
                  Column(
                    children: [
                      TextField(
                        controller: _brregCtrl,
                        decoration: InputDecoration(
                          hintText: 'Firmanavn eller org.nr…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _brregSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                        onChanged: _onBrregSearch,
                      ),
                      const SizedBox(height: 8),
                      if (_brregCreating)
                        const Expanded(
                          child: Center(
                              child: CircularProgressIndicator()),
                        )
                      else
                        Expanded(
                          child: _brregResults.isEmpty
                              ? Center(
                                  child: Text(
                                    _brregCtrl.text.isEmpty
                                        ? 'Søk etter bedrift i Enhetsregisteret'
                                        : 'Ingen treff',
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _brregResults.length,
                                  itemBuilder: (ctx, i) {
                                    final c = _brregResults[i];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(
                                          Icons.language, size: 18),
                                      title: Text(c.name,
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w700)),
                                      subtitle: Text(
                                          '${c.orgNr}  ·  ${c.city ?? ''}'),
                                      onTap: () => _selectBrreg(c),
                                    );
                                  },
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
      ],
    );
  }
}

// ===========================================================================
// GIG ROW
// ===========================================================================

class _GigRow extends StatelessWidget {
  final Map<String, dynamic> gig;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;

  const _GigRow({
    required this.gig,
    required this.onTap,
    required this.onCancel,
    required this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFrom = gig['date_from'] as String?;
    final dateTo = gig['date_to'] as String?;
    final venue = gig['venue_name'] as String? ?? '';
    final city = gig['city'] as String? ?? '';
    final firma = gig['customer_firma'] as String? ?? '';
    final custName = gig['customer_name'] as String? ?? '';
    final status = gig['status'] as String? ?? 'inquiry';
    final type = gig['type'] as String? ?? 'gig';

    final shows = (gig['gig_shows'] as List<dynamic>? ?? [])
        .map((s) => s['show_name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');

    String dateLabel = '';
    if (dateFrom != null) {
      final dfmt = DateFormat('dd.MM.yyyy');
      final from = dfmt.format(DateTime.parse(dateFrom));
      if (dateTo != null && dateTo != dateFrom) {
        dateLabel = '$from – ${dfmt.format(DateTime.parse(dateTo))}';
      } else {
        dateLabel = from;
      }
    }

    final locationLine =
        [venue, city].where((s) => s.isNotEmpty).join(' · ');
    final customerLine =
        [firma, custName].where((s) => s.isNotEmpty).join(' — ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: onSelect != null ? (_) => onSelect!() : null,
              ),
              const SizedBox(width: 4),
            ],
            SizedBox(
              width: 120,
              child: Text(
                dateLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type != 'gig') ...[
                    Text(
                      const {'rehearsal': 'Øvelse', 'meeting': 'Møte', 'other': 'Annet'}[type] ?? type,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    if (locationLine.isNotEmpty)
                      Text(
                        locationLine,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                  ] else ...[
                    if (locationLine.isNotEmpty)
                      Text(
                        locationLine,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    if (customerLine.isNotEmpty)
                      Text(
                        customerLine,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    if (shows.isNotEmpty)
                      Text(
                        shows,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                  ],
                ],
              ),
            ),
            if (status == 'cancelled') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            if (type != 'gig' && status != 'cancelled') ...[
              Builder(builder: (_) {
                final badgeColor = const {
                  'rehearsal': Colors.purple,
                  'meeting': Colors.teal,
                  'other': Colors.blueGrey,
                }[type] ?? Colors.grey;
                final badgeLabel = const {
                  'rehearsal': 'Øvelse',
                  'meeting': 'Møte',
                  'other': 'Annet',
                }[type] ?? type;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badgeColor),
                  ),
                );
              }),
              const SizedBox(width: 8),
            ],
            if (type == 'gig' && status != 'cancelled')
              _GigStatusBadge(status: status),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
              onSelected: (v) {
                if (v == 'cancel') onCancel();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                if (status != 'cancelled')
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Row(
                      children: [
                        Icon(Icons.cancel_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Avlys'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Slett', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// STATUS BADGE
// ===========================================================================

class _GigStatusBadge extends StatelessWidget {
  final String status;
  const _GigStatusBadge({required this.status});

  static const _colors = {
    'inquiry': Colors.orange,
    'confirmed': Colors.green,
    'cancelled': Colors.red,
    'invoiced': Colors.blue,
    'completed': Colors.grey,
  };

  static const _labels = {
    'inquiry': 'Forespørsel',
    'confirmed': 'Bekreftet',
    'cancelled': 'Avlyst',
    'invoiced': 'Fakturert',
    'completed': 'Fullført',
  };

  @override
  Widget build(BuildContext context) {
    final color = (_colors[status] ?? Colors.grey) as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _labels[status] ?? status,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
