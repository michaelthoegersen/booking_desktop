import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';
import '../../widgets/new_company_dialog.dart';

class MgmtGigsPage extends StatefulWidget {
  const MgmtGigsPage({super.key});

  @override
  State<MgmtGigsPage> createState() => _MgmtGigsPageState();
}

class _MgmtGigsPageState extends State<MgmtGigsPage> {
  final _sb = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _companyId;
  List<Map<String, dynamic>> _gigs = [];
  String _search = '';
  String _statusFilter = 'all';

  static const _statuses = ['all', 'upcoming', 'confirmed', 'invoiced'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      final profile = await _sb
          .from('profiles')
          .select('company_id')
          .eq('id', uid)
          .maybeSingle();
      _companyId = profile?['company_id'] as String?;

      if (_companyId == null) {
        setState(() => _loading = false);
        return;
      }

      final gigs = await _sb
          .from('gigs')
          .select('*, gig_shows(show_name)')
          .eq('company_id', _companyId!)
          .order('date_from', ascending: true);

      _gigs = List<Map<String, dynamic>>.from(gigs);
    } catch (e) {
      debugPrint('Gigs load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _gigs;

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

    final gigId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewGigDialog(managementCompanyId: _companyId!),
    );

    if (gigId != null && mounted) {
      context.go('/m/gigs/$gigId');
    } else {
      await _load();
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Gigs',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search gigs…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openNewGigDialog,
                icon: const Icon(Icons.add),
                label: const Text('Ny event'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status filter chips
          Row(
            children: _statuses.map((s) {
              final selected = _statusFilter == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s == 'all' ? 'All' : _capitalize(s)),
                  selected: selected,
                  onSelected: (_) => setState(() => _statusFilter = s),
                  selectedColor: Colors.black,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : CssTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _search.isNotEmpty || _statusFilter != 'all'
                              ? 'No gigs match your filter'
                              : 'No gigs yet. Create your first gig!',
                          style: const TextStyle(color: CssTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final gig = _filtered[i];
                          return _GigRow(
                            gig: gig,
                            onTap: () => context.go('/m/gigs/${gig['id']}'),
                            onDelete: () => _confirmDelete(gig),
                          );
                        },
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

  const _NewGigDialog({required this.managementCompanyId});

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
  final _inearPriceCtrl = TextEditingController(text: '7000');
  final _transportKmCtrl = TextEditingController();
  final _transportPriceCtrl = TextEditingController();
  final _extraDescCtrl = TextEditingController();
  final _extraPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _infoFromOrgCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
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
        'inear_price': double.tryParse(_inearPriceCtrl.text) ?? 7000,
        'transport_km': int.tryParse(_transportKmCtrl.text),
        'transport_price': double.tryParse(_transportPriceCtrl.text),
        'extra_desc': n(_extraDescCtrl.text),
        'extra_price': double.tryParse(_extraPriceCtrl.text),
        'notes_for_contract': n(_notesCtrl.text),
        'info_from_organizer': n(_infoFromOrgCtrl.text),
        'created_by': _sb.auth.currentUser?.id,
      }).select('id').single();

      if (mounted) Navigator.of(context).pop(res['id'] as String);
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
                _type == 'gig' ? 'Ny Gig' : 'Ny Øvelse',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),

              // Type toggle
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gig', label: Text('Gig'), icon: Icon(Icons.music_note, size: 16)),
                  ButtonSegment(value: 'rehearsal', label: Text('Øvelse'), icon: Icon(Icons.piano, size: 16)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 16),

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
                                        child: Text(s),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _status = v ?? _status),
                            ),
                          ),
                        ],
                      ),

                      // ── LOCATION ────────────────────────────────────────
                      _sec('Spillested'),
                      _row([
                        _tf(_venueCtrl, 'Venue', flex: 2),
                        _tf(_cityCtrl, 'City'),
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
                      _sec('Show-beskrivelse'),
                      _tfFull(_showDescCtrl, 'Beskriv showet', maxLines: 2),
                      ], // end if gig

                      // ── SCHEDULE ────────────────────────────────────────
                      _sec('Timeplan'),
                      _row([
                        _tf(_meetingTimeCtrl, 'Oppmøte (HH:mm)'),
                        _tf(_getInTimeCtrl, 'Get-in (HH:mm)'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_rehearsalTimeCtrl, 'Prøver (HH:mm)'),
                        _tf(_performanceTimeCtrl, 'Opptreden (HH:mm)'),
                      ]),
                      const SizedBox(height: 8),
                      _row([
                        _tf(_getOutTimeCtrl, 'Get-out (HH:mm)'),
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
                      _tfFull(_notesCtrl, 'Notat for kontrakt',
                          maxLines: 2),
                      const SizedBox(height: 8),
                      _tfFull(_infoFromOrgCtrl, 'Info fra arrangør',
                          maxLines: 2),
                      ], // end if gig

                      // ── REHEARSAL NOTES ─────────────────────────────────
                      if (_type == 'rehearsal') ...[
                      _sec('Notat'),
                      _tfFull(_notesCtrl, 'Notat (intern)', maxLines: 3),
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
                          : Text(_type == 'gig' ? 'Opprett gig' : 'Opprett øvelse'),
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

  static Widget _sec(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: CssTheme.textMuted,
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
    TextInputType keyboardType = TextInputType.text,
  }) {
    final field = TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
    );
    if (width != null) return SizedBox(width: width, child: field);
    return Expanded(flex: flex, child: field);
  }

  static Widget _tfFull(
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

  const _CustomerPicker({
    required this.companies,
    required this.selectedCompany,
    required this.loading,
    required this.onSelected,
    required this.onClear,
    required this.onNewCompany,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomerPickerDialog(companies: companies),
    );
    if (result != null) onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
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
                border: Border.all(color: CssTheme.outline),
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
                        ? CssTheme.textMuted
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: loading
                        ? const Text('Laster kunder…',
                            style: TextStyle(color: CssTheme.textMuted))
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
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: CssTheme.textMuted),
                                    ),
                                ],
                              )
                            : const Text(
                                'Velg kunde…',
                                style:
                                    TextStyle(color: CssTheme.textMuted),
                              ),
                  ),
                  if (selected != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Fjern kunde',
                      onPressed: onClear,
                    )
                  else
                    const Icon(Icons.arrow_drop_down,
                        color: CssTheme.textMuted),
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

  const _CustomerPickerDialog({required this.companies});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.companies
        : widget.companies.where((c) {
            final name = (c['name'] as String? ?? '').toLowerCase();
            final city = (c['city'] as String? ?? '').toLowerCase();
            final q = _query.toLowerCase();
            return name.contains(q) || city.contains(q);
          }).toList();

    return AlertDialog(
      title: const Text('Velg kunde'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
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
                  ? const Center(
                      child: Text('Ingen treff',
                          style: TextStyle(color: CssTheme.textMuted)))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final c = filtered[i];
                        final name = c['name'] as String? ?? '';
                        final city = c['city'] as String?;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.business_outlined,
                              size: 18),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: city != null
                              ? Text(city,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: CssTheme.textMuted))
                              : null,
                          onTap: () => Navigator.pop(ctx, c),
                        );
                      },
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
  final VoidCallback onDelete;

  const _GigRow({required this.gig, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
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
          color: CssTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CssTheme.outline),
        ),
        child: Row(
          children: [
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
                  if (locationLine.isNotEmpty)
                    Text(
                      locationLine,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  if (customerLine.isNotEmpty)
                    Text(
                      customerLine,
                      style: const TextStyle(
                          color: CssTheme.textMuted, fontSize: 13),
                    ),
                  if (shows.isNotEmpty)
                    Text(
                      shows,
                      style: const TextStyle(
                          fontSize: 12, color: CssTheme.textMuted),
                    ),
                ],
              ),
            ),
            if (type == 'rehearsal') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            _GigStatusBadge(status: status),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: CssTheme.textMuted),
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
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
    'inquiry': 'Inquiry',
    'confirmed': 'Confirmed',
    'cancelled': 'Cancelled',
    'invoiced': 'Invoiced',
    'completed': 'Completed',
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
