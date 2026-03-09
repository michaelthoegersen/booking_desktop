import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';

class MgmtTourDetailPage extends StatefulWidget {
  final String tourId;

  const MgmtTourDetailPage({super.key, required this.tourId});

  @override
  State<MgmtTourDetailPage> createState() => _MgmtTourDetailPageState();
}

class _MgmtTourDetailPageState extends State<MgmtTourDetailPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late TabController _tabCtrl;

  bool _loading = true;
  Map<String, dynamic>? _tour;
  String? get _companyId => activeCompanyNotifier.value?.id;

  List<Map<String, dynamic>> _shows = [];
  List<Map<String, dynamic>> _itinerary = [];
  List<Map<String, dynamic>> _team = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onCompanyChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tour = await _sb
          .from('management_tours')
          .select('*')
          .eq('id', widget.tourId)
          .maybeSingle();
      _tour = tour;

      final shows = await _sb
          .from('management_shows')
          .select('*')
          .eq('tour_id', widget.tourId)
          .order('date');
      _shows = List<Map<String, dynamic>>.from(shows);

      final itinerary = await _sb
          .from('management_itinerary')
          .select('*')
          .eq('tour_id', widget.tourId)
          .order('date')
          .order('sort_order');
      _itinerary = List<Map<String, dynamic>>.from(itinerary);

      final team = await _sb
          .from('management_team')
          .select('*')
          .eq('tour_id', widget.tourId)
          .order('name');
      _team = List<Map<String, dynamic>>.from(team);
    } catch (e) {
      debugPrint('Tour detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ------ SHOWS ------

  Future<void> _addShow() async {
    DateTime? date;
    final venueCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final countryCtrl = TextEditingController(text: 'NO');
    String status = 'confirmed';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Legg til show'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(date != null
                      ? DateFormat('dd.MM.yyyy').format(date!)
                      : 'Velg dato *'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setS(() => date = d);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: venueCtrl,
                  decoration: const InputDecoration(labelText: 'Spillested'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'By'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: countryCtrl,
                  decoration: const InputDecoration(labelText: 'Land'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ['confirmed', 'hold', 'cancelled']
                      .map((s) => DropdownMenuItem(value: s, child: Text(_StatusBadge._statusLabels[s] ?? s)))
                      .toList(),
                  onChanged: (v) => setS(() => status = v ?? 'confirmed'),
                ),
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
                if (date == null) return;
                try {
                  await _sb.from('management_shows').insert({
                    'tour_id': widget.tourId,
                    'date': DateFormat('yyyy-MM-dd').format(date!),
                    'venue_name': venueCtrl.text.trim(),
                    'city': cityCtrl.text.trim(),
                    'country': countryCtrl.text.trim(),
                    'status': status,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett show?'),
        content: const Text('Handlingen kan ikke angres.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _sb.from('management_shows').delete().eq('id', showId);
      await _load();
    }
  }

  Future<void> _openBusRequestDialog(Map<String, dynamic> show) async {
    final fromCityCtrl =
        TextEditingController(text: show['city'] as String? ?? '');
    final toCityCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final paxCtrl = TextEditingController();
    DateTime? dateFrom;
    DateTime? dateTo;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Bestill buss'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(dateFrom != null
                            ? DateFormat('dd.MM.yyyy').format(dateFrom!)
                            : 'Fra dato *'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: show['date'] != null
                                ? DateTime.parse(show['date'])
                                : DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setS(() => dateFrom = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(dateTo != null
                            ? DateFormat('dd.MM.yyyy').format(dateTo!)
                            : 'Til dato *'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: dateFrom ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setS(() => dateTo = d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fromCityCtrl,
                  decoration: const InputDecoration(labelText: 'Fra by'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: toCityCtrl,
                  decoration: const InputDecoration(labelText: 'Til by'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: paxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Passasjerer',
                    suffixText: 'pax',
                  ),
                ),
                const SizedBox(height: 10),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                if (dateFrom == null || dateTo == null) return;
                try {
                  await _sb.from('bus_requests').insert({
                    'company_id': _companyId,
                    'tour_id': widget.tourId,
                    'show_id': show['id'],
                    'date_from': DateFormat('yyyy-MM-dd').format(dateFrom!),
                    'date_to': DateFormat('yyyy-MM-dd').format(dateTo!),
                    'from_city': fromCityCtrl.text.trim(),
                    'to_city': toCityCtrl.text.trim(),
                    'pax': int.tryParse(paxCtrl.text.trim()),
                    'notes': notesCtrl.text.trim(),
                    'status': 'pending',
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bussforespørsel sendt!')),
                    );
                  }
                } catch (e) {
                  debugPrint('Bus request error: $e');
                }
              },
              child: const Text('Send forespørsel'),
            ),
          ],
        ),
      ),
    );
  }

  // ------ ITINERARY ------

  Future<void> _addItinerary() async {
    DateTime? date;
    final descCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    String type = 'note';
    TimeOfDay? time;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Legg til reiseplan'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(date != null
                            ? DateFormat('dd.MM.yyyy').format(date!)
                            : 'Dato *'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setS(() => date = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(time != null
                            ? time!.format(ctx)
                            : 'Tid (valgfritt)'),
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.now(),
                          );
                          if (t != null) setS(() => time = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    'travel',
                    'check_in',
                    'soundcheck',
                    'doors',
                    'show',
                    'hotel',
                    'load_out',
                    'note',
                  ]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setS(() => type = v ?? 'note'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Beskrivelse *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Sted'),
                ),
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
                if (date == null || descCtrl.text.trim().isEmpty) return;
                try {
                  await _sb.from('management_itinerary').insert({
                    'tour_id': widget.tourId,
                    'date': DateFormat('yyyy-MM-dd').format(date!),
                    if (time != null)
                      'time':
                          '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}:00',
                    'type': type,
                    'description': descCtrl.text.trim(),
                    'location': locationCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Add itinerary error: $e');
                }
              },
              child: const Text('Legg til'),
            ),
          ],
        ),
      ),
    );
  }

  // ------ TEAM ------

  Future<void> _addTeamMember() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String role = 'crew';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Legg til teammedlem'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Navn *'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Rolle'),
                  items: [
                    'artist',
                    'tour_manager',
                    'production',
                    'crew',
                    'driver',
                    'other',
                  ]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setS(() => role = v ?? 'crew'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'E-post'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notater'),
                ),
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
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await _sb.from('management_team').insert({
                    'tour_id': widget.tourId,
                    'name': nameCtrl.text.trim(),
                    'role': role,
                    'email': emailCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Add team member error: $e');
                }
              },
              child: const Text('Legg til'),
            ),
          ],
        ),
      ),
    );
  }

  // ------ INFO EDIT ------

  Future<void> _editTourInfo() async {
    if (_tour == null) return;
    final nameCtrl = TextEditingController(text: _tour!['name'] as String?);
    final artistCtrl =
        TextEditingController(text: _tour!['artist'] as String?);
    final notesCtrl = TextEditingController(text: _tour!['notes'] as String?);
    String status = _tour!['status'] as String? ?? 'planning';
    DateTime? start = _tour!['tour_start'] != null
        ? DateTime.parse(_tour!['tour_start'])
        : null;
    DateTime? end = _tour!['tour_end'] != null
        ? DateTime.parse(_tour!['tour_end'])
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Rediger turnéinfo'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Turnénavn'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: artistCtrl,
                    decoration: const InputDecoration(labelText: 'Artist'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: ['planning', 'active', 'completed', 'cancelled']
                        .map((s) => DropdownMenuItem(value: s, child: Text(_StatusBadge._statusLabels[s] ?? s)))
                        .toList(),
                    onChanged: (v) => setS(() => status = v ?? 'planning'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(start != null
                              ? DateFormat('dd.MM.yyyy').format(start!)
                              : 'Startdato'),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: start ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setS(() => start = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(end != null
                              ? DateFormat('dd.MM.yyyy').format(end!)
                              : 'Sluttdato'),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: end ?? start ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setS(() => end = d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notater'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _sb.from('management_tours').update({
                    'name': nameCtrl.text.trim(),
                    'artist': artistCtrl.text.trim(),
                    'status': status,
                    'tour_start':
                        start != null ? DateFormat('yyyy-MM-dd').format(start!) : null,
                    'tour_end':
                        end != null ? DateFormat('yyyy-MM-dd').format(end!) : null,
                    'notes': notesCtrl.text.trim(),
                    'updated_at': DateTime.now().toIso8601String(),
                  }).eq('id', widget.tourId);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Edit tour error: $e');
                }
              },
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
  }

  // ------ DELETE TOUR ------

  Future<void> _confirmDeleteTour() async {
    final name = _tour?['name'] as String? ?? 'denne touren';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett tour'),
        content: Text(
          'Er du sikker på at du vil slette "$name"?\n\n'
          'Alle shows, itinerary og teammedlemmer tilknyttet touren vil også slettes.',
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
      await _sb
          .from('management_tours')
          .delete()
          .eq('id', widget.tourId);
      if (mounted) context.go('/m/tours');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

  // ------ BUILD ------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tour == null) {
      return const Center(child: Text('Turné ikke funnet'));
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tour!['name'] as String? ?? '',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    _tour!['artist'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              _StatusBadge(status: _tour!['status'] as String? ?? 'planning'),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'delete') _confirmDeleteTour();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Slett tour', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabCtrl,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: const [
              Tab(text: 'Shows'),
              Tab(text: 'Reiseplan'),
              Tab(text: 'Team'),
              Tab(text: 'Info'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _ShowsTab(
                  shows: _shows,
                  onAdd: _addShow,
                  onDelete: _deleteShow,
                  onBookBus: _openBusRequestDialog,
                ),
                _ItineraryTab(
                  itinerary: _itinerary,
                  onAdd: _addItinerary,
                ),
                _TeamTab(
                  team: _team,
                  onAdd: _addTeamMember,
                ),
                _InfoTab(
                  tour: _tour!,
                  onEdit: _editTourInfo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------ SHOWS TAB ------

class _ShowsTab extends StatelessWidget {
  final List<Map<String, dynamic>> shows;
  final VoidCallback onAdd;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(Map<String, dynamic>) onBookBus;

  const _ShowsTab({
    required this.shows,
    required this.onAdd,
    required this.onDelete,
    required this.onBookBus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Legg til show'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: shows.isEmpty
              ? Center(
                  child: Text(
                    'Ingen shows ennå',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: shows.length,
                  itemBuilder: (context, i) {
                    final show = shows[i];
                    return _ShowRow(
                      show: show,
                      onDelete: () => onDelete(show['id']),
                      onBookBus: () => onBookBus(show),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ShowRow extends StatelessWidget {
  final Map<String, dynamic> show;
  final VoidCallback onDelete;
  final VoidCallback onBookBus;

  const _ShowRow({
    required this.show,
    required this.onDelete,
    required this.onBookBus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = show['date'] as String?;
    final venue = show['venue_name'] as String? ?? '';
    final city = show['city'] as String? ?? '';
    final country = show['country'] as String? ?? '';
    final status = show['status'] as String? ?? 'confirmed';
    final hasBusRequest = show['bus_request_id'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            alignment: Alignment.center,
            child: Column(
              children: [
                Text(
                  date != null
                      ? DateFormat('MMM').format(DateTime.parse(date))
                      : '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  date != null
                      ? DateFormat('d').format(DateTime.parse(date))
                      : '',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue.isNotEmpty ? venue : '(No venue)',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  [city, country].where((s) => s.isNotEmpty).join(', '),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _StatusBadge(status: status),
          const SizedBox(width: 8),
          if (!hasBusRequest)
            TextButton.icon(
              onPressed: onBookBus,
              icon: const Icon(Icons.directions_bus, size: 16),
              label: const Text('Bestill buss'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Buss bestilt',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

// ------ ITINERARY TAB ------

class _ItineraryTab extends StatelessWidget {
  final List<Map<String, dynamic>> itinerary;
  final VoidCallback onAdd;

  const _ItineraryTab({
    required this.itinerary,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Group by date
    final Map<String, List<Map<String, dynamic>>> byDate = {};
    for (final item in itinerary) {
      final date = item['date'] as String? ?? '';
      byDate.putIfAbsent(date, () => []).add(item);
    }
    final dates = byDate.keys.toList()..sort();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Legg til'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: itinerary.isEmpty
              ? Center(
                  child: Text(
                    'Ingen reiseplan ennå',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: dates.length,
                  itemBuilder: (context, i) {
                    final date = dates[i];
                    final items = byDate[date]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            DateFormat('EEEE, d MMMM')
                                .format(DateTime.parse(date)),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        ...items.map((item) => _ItineraryRow(item: item)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ItineraryRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItineraryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = item['time'] as String?;
    final type = item['type'] as String? ?? 'note';
    final description = item['description'] as String? ?? '';
    final location = item['location'] as String? ?? '';

    final typeColors = {
      'travel': Colors.blue,
      'check_in': Colors.purple,
      'soundcheck': Colors.orange,
      'doors': Colors.teal,
      'show': Colors.green,
      'hotel': Colors.indigo,
      'load_out': Colors.brown,
      'note': Colors.grey,
    };

    final color = typeColors[type] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          if (time != null)
            SizedBox(
              width: 48,
              child: Text(
                time.substring(0, 5),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              type.replaceAll('_', ' '),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (location.isNotEmpty)
                  Text(
                    location,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
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

// ------ TEAM TAB ------

class _TeamTab extends StatelessWidget {
  final List<Map<String, dynamic>> team;
  final VoidCallback onAdd;

  const _TeamTab({required this.team, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add),
              label: const Text('Legg til medlem'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: team.isEmpty
              ? Center(
                  child: Text(
                    'Ingen teammedlemmer ennå',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: team.length,
                  itemBuilder: (context, i) =>
                      _TeamMemberRow(member: team[i]),
                ),
        ),
      ],
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  const _TeamMemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = member['name'] as String? ?? '';
    final role = member['role'] as String? ?? '';
    final email = member['email'] as String? ?? '';
    final phone = member['phone'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.black,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  role.replaceAll('_', ' '),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                if (email.isNotEmpty || phone.isNotEmpty)
                  Text(
                    [email, phone]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
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

// ------ INFO TAB ------

class _InfoTab extends StatelessWidget {
  final Map<String, dynamic> tour;
  final VoidCallback onEdit;

  const _InfoTab({required this.tour, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = tour['tour_start'] as String?;
    final end = tour['tour_end'] as String?;
    final notes = tour['notes'] as String? ?? '';
    final createdAt = tour['created_at'] as String?;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
                label: const Text('Rediger'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Turnénavn', value: tour['name'] as String? ?? ''),
                _InfoRow(label: 'Artist', value: tour['artist'] as String? ?? ''),
                _InfoRow(label: 'Status', value: _StatusBadge._statusLabels[tour['status'] as String? ?? ''] ?? (tour['status'] as String? ?? '')),
                if (start != null)
                  _InfoRow(
                    label: 'Startdato',
                    value: DateFormat('dd.MM.yyyy').format(DateTime.parse(start)),
                  ),
                if (end != null)
                  _InfoRow(
                    label: 'Sluttdato',
                    value: DateFormat('dd.MM.yyyy').format(DateTime.parse(end)),
                  ),
                if (notes.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Notater',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(notes),
                ],
                if (createdAt != null) ...[
                  const Divider(height: 24),
                  Text(
                    'Opprettet ${DateFormat('dd.MM.yyyy').format(DateTime.parse(createdAt))}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  static const _statusLabels = {
    'planning': 'Planlegger',
    'active': 'Aktiv',
    'completed': 'Fullført',
    'cancelled': 'Avlyst',
    'confirmed': 'Bekreftet',
    'hold': 'Hold',
  };

  @override
  Widget build(BuildContext context) {
    final colors = {
      'planning': Colors.blue,
      'active': Colors.green,
      'completed': Colors.grey,
      'cancelled': Colors.red,
      'confirmed': Colors.green,
      'hold': Colors.orange,
    };
    final color = colors[status] ?? Colors.grey;
    final label = _statusLabels[status] ?? status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
