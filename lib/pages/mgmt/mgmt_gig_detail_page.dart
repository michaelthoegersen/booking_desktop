import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';
import '../../services/intensjonsavtale_pdf_service.dart';
import '../../services/email_service.dart';

class MgmtGigDetailPage extends StatefulWidget {
  final String gigId;

  const MgmtGigDetailPage({super.key, required this.gigId});

  @override
  State<MgmtGigDetailPage> createState() => _MgmtGigDetailPageState();
}

class _MgmtGigDetailPageState extends State<MgmtGigDetailPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late TabController _tabCtrl;

  bool _loading = true;
  Map<String, dynamic>? _gig;

  List<Map<String, dynamic>> _shows = [];
  List<Map<String, dynamic>> _crew = [];
  List<Map<String, dynamic>> _showTypes = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
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
      final desiredLength = isRehearsal ? 1 : 4;
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

      final crew = await _sb
          .from('gig_crew')
          .select('*')
          .eq('gig_id', widget.gigId)
          .order('sort_order');
      _crew = List<Map<String, dynamic>>.from(crew);

      final types = await _sb
          .from('show_types')
          .select('*')
          .eq('active', true)
          .order('sort_order');
      _showTypes = List<Map<String, dynamic>>.from(types);
    } catch (e) {
      debugPrint('Gig detail load error: $e');
    }
    if (mounted) setState(() => _loading = false);
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
  // EDIT GIG INFO DIALOG
  // -------------------------------------------------------------------------

  Future<void> _editGigInfo() async {
    if (_gig == null) return;

    DateTime? dateFrom = _gig!['date_from'] != null
        ? DateTime.parse(_gig!['date_from'])
        : null;
    DateTime? dateTo = _gig!['date_to'] != null
        ? DateTime.parse(_gig!['date_to'])
        : null;

    final c = <String, TextEditingController>{
      'venue': TextEditingController(text: _gig!['venue_name'] ?? ''),
      'city': TextEditingController(text: _gig!['city'] ?? ''),
      'country': TextEditingController(text: _gig!['country'] ?? 'NO'),
      'firma': TextEditingController(text: _gig!['customer_firma'] ?? ''),
      'custName': TextEditingController(text: _gig!['customer_name'] ?? ''),
      'phone': TextEditingController(text: _gig!['customer_phone'] ?? ''),
      'email': TextEditingController(text: _gig!['customer_email'] ?? ''),
      'orgNr': TextEditingController(text: _gig!['customer_org_nr'] ?? ''),
      'address': TextEditingController(text: _gig!['customer_address'] ?? ''),
      'responsible': TextEditingController(text: _gig!['responsible'] ?? ''),
      'showDesc': TextEditingController(text: _gig!['show_desc'] ?? ''),
      'meetingTime': TextEditingController(text: _gig!['meeting_time'] ?? ''),
      'getInTime': TextEditingController(text: _gig!['get_in_time'] ?? ''),
      'rehearsalTime': TextEditingController(text: _gig!['rehearsal_time'] ?? ''),
      'performanceTime': TextEditingController(text: _gig!['performance_time'] ?? ''),
      'getOutTime': TextEditingController(text: _gig!['get_out_time'] ?? ''),
      'meetingNotes': TextEditingController(text: _gig!['meeting_notes'] ?? ''),
      'stageShape': TextEditingController(text: _gig!['stage_shape'] ?? ''),
      'stageSize': TextEditingController(text: _gig!['stage_size'] ?? ''),
      'stageNotes': TextEditingController(text: _gig!['stage_notes'] ?? ''),
      'inearPrice': TextEditingController(
          text: _gig!['inear_price']?.toString() ?? '7000'),
      'transportKm': TextEditingController(
          text: _gig!['transport_km']?.toString() ?? ''),
      'transportPrice': TextEditingController(
          text: _gig!['transport_price']?.toString() ?? ''),
      'extraDesc': TextEditingController(text: _gig!['extra_desc'] ?? ''),
      'extraPrice': TextEditingController(
          text: _gig!['extra_price']?.toString() ?? ''),
      'notesForContract': TextEditingController(
          text: _gig!['notes_for_contract'] ?? ''),
      'infoFromOrganizer': TextEditingController(
          text: _gig!['info_from_organizer'] ?? ''),
    };

    bool inearFromUs = _gig!['inear_from_us'] == true;
    bool playbackFromUs = _gig!['playback_from_us'] != false;
    bool invoiceOnEhf = _gig!['invoice_on_ehf'] == true;
    String status = _gig!['status'] as String? ?? 'inquiry';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit Gig Info'),
          content: SizedBox(
            width: 640,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dates
                  const _SectionHeader('Dates'),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(dateFrom != null
                              ? DateFormat('dd.MM.yyyy').format(dateFrom!)
                              : 'Date from *'),
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
                          label: Text(dateTo != null
                              ? DateFormat('dd.MM.yyyy').format(dateTo!)
                              : 'Date to'),
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
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Status + responsible
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: ['inquiry', 'confirmed', 'invoiced', 'completed', 'cancelled']
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setS(() => status = v ?? status),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['responsible']!, 'Responsible')),
                    ],
                  ),

                  // Venue / City / Country
                  const _SectionHeader('Location'),
                  _tf(c['venue']!, 'Venue'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _tf(c['city']!, 'City')),
                      const SizedBox(width: 8),
                      SizedBox(width: 100, child: _tf(c['country']!, 'Country')),
                    ],
                  ),

                  // Customer
                  const _SectionHeader('Customer'),
                  _tf(c['firma']!, 'Firma / Company'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _tf(c['custName']!, 'Contact name')),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['phone']!, 'Phone')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _tf(c['email']!, 'Email')),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['orgNr']!, 'Org.nr')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _tf(c['address']!, 'Address'),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Invoice on EHF'),
                    value: invoiceOnEhf,
                    onChanged: (v) => setS(() => invoiceOnEhf = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),

                  // Show desc
                  const _SectionHeader('Show Description'),
                  _tf(c['showDesc']!, 'Show description', maxLines: 2),

                  // Schedule
                  const _SectionHeader('Schedule'),
                  Row(
                    children: [
                      Expanded(child: _tf(c['meetingTime']!, 'Oppmøte (HH:mm)')),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['getInTime']!, 'Get-in (HH:mm)')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _tf(c['rehearsalTime']!, 'Prøver (HH:mm)')),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['performanceTime']!, 'Opptreden (HH:mm)')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _tf(c['getOutTime']!, 'Get-out (HH:mm)'),
                  const SizedBox(height: 8),
                  _tf(c['meetingNotes']!, 'Oppmøtenotat', maxLines: 2),

                  // Stage
                  const _SectionHeader('Stage'),
                  Row(
                    children: [
                      Expanded(child: _tf(c['stageShape']!, 'Stage shape')),
                      const SizedBox(width: 8),
                      Expanded(child: _tf(c['stageSize']!, 'Stage size')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _tf(c['stageNotes']!, 'Stage notes', maxLines: 2),

                  // Tech
                  const _SectionHeader('Teknikk'),
                  SwitchListTile(
                    title: const Text('In-ear fra oss'),
                    value: inearFromUs,
                    onChanged: (v) => setS(() => inearFromUs = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (inearFromUs)
                    _tf(c['inearPrice']!, 'In-ear pris (kr)',
                        keyboardType: TextInputType.number),
                  SwitchListTile(
                    title: const Text('Playback fra oss'),
                    value: playbackFromUs,
                    onChanged: (v) => setS(() => playbackFromUs = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),

                  // Transport
                  const _SectionHeader('Transport'),
                  Row(
                    children: [
                      Expanded(
                          child: _tf(c['transportKm']!, 'Km',
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _tf(c['transportPrice']!, 'Transport pris (kr)',
                              keyboardType: TextInputType.number)),
                    ],
                  ),

                  // Extra
                  const _SectionHeader('Extra'),
                  _tf(c['extraDesc']!, 'Extra beskrivelse'),
                  const SizedBox(height: 8),
                  _tf(c['extraPrice']!, 'Extra pris (kr)',
                      keyboardType: TextInputType.number),

                  // Notes
                  const _SectionHeader('Notes'),
                  _tf(c['notesForContract']!, 'Notes for contract', maxLines: 3),
                  const SizedBox(height: 8),
                  _tf(c['infoFromOrganizer']!, 'Info from organizer', maxLines: 3),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (dateFrom == null) return;
                try {
                  final df = DateFormat('yyyy-MM-dd');
                  await _sb.from('gigs').update({
                    'date_from': df.format(dateFrom!),
                    'date_to': dateTo != null ? df.format(dateTo!) : null,
                    'venue_name': c['venue']!.text.trim().orNull,
                    'city': c['city']!.text.trim().orNull,
                    'country': c['country']!.text.trim().orNull,
                    'customer_firma': c['firma']!.text.trim().orNull,
                    'customer_name': c['custName']!.text.trim().orNull,
                    'customer_phone': c['phone']!.text.trim().orNull,
                    'customer_email': c['email']!.text.trim().orNull,
                    'customer_org_nr': c['orgNr']!.text.trim().orNull,
                    'customer_address': c['address']!.text.trim().orNull,
                    'invoice_on_ehf': invoiceOnEhf,
                    'responsible': c['responsible']!.text.trim().orNull,
                    'show_desc': c['showDesc']!.text.trim().orNull,
                    'meeting_time': c['meetingTime']!.text.trim().orNull,
                    'get_in_time': c['getInTime']!.text.trim().orNull,
                    'rehearsal_time': c['rehearsalTime']!.text.trim().orNull,
                    'performance_time': c['performanceTime']!.text.trim().orNull,
                    'get_out_time': c['getOutTime']!.text.trim().orNull,
                    'meeting_notes': c['meetingNotes']!.text.trim().orNull,
                    'stage_shape': c['stageShape']!.text.trim().orNull,
                    'stage_size': c['stageSize']!.text.trim().orNull,
                    'stage_notes': c['stageNotes']!.text.trim().orNull,
                    'inear_from_us': inearFromUs,
                    'playback_from_us': playbackFromUs,
                    'inear_price': double.tryParse(c['inearPrice']!.text),
                    'transport_km': int.tryParse(c['transportKm']!.text),
                    'transport_price': double.tryParse(c['transportPrice']!.text),
                    'extra_desc': c['extraDesc']!.text.trim().orNull,
                    'extra_price': double.tryParse(c['extraPrice']!.text),
                    'notes_for_contract': c['notesForContract']!.text.trim().orNull,
                    'info_from_organizer': c['infoFromOrganizer']!.text.trim().orNull,
                    'status': status,
                    'updated_at': DateTime.now().toIso8601String(),
                  }).eq('id', widget.gigId);

                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Update gig error: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // DELETE GIG
  // -------------------------------------------------------------------------

  Future<void> _confirmDeleteGig() async {
    final venue = _gig?['venue_name'] as String?;
    final dateFrom = _gig?['date_from'] as String?;
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
          title: const Text('Add Show'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  decoration: const InputDecoration(labelText: 'Show type'),
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
              child: const Text('Cancel'),
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
              child: const Text('Add'),
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
  // CREW
  // -------------------------------------------------------------------------

  Future<void> _addCrewMember() async {
    final nameCtrl = TextEditingController();
    String role = 'skarp';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Crew Member'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(nameCtrl, 'Name'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: ['skarp', 'bass', 'danser', 'annet']
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_roleLabel(r)),
                          ))
                      .toList(),
                  onChanged: (v) => setS(() => role = v ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await _sb.from('gig_crew').insert({
                    'gig_id': widget.gigId,
                    'name': nameCtrl.text.trim(),
                    'role': role,
                    'confirmed': false,
                    'sort_order': _crew.length,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  debugPrint('Add crew error: $e');
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCrewConfirmed(String crewId, bool current) async {
    try {
      await _sb
          .from('gig_crew')
          .update({'confirmed': !current})
          .eq('id', crewId);
      await _load();
    } catch (e) {
      debugPrint('Toggle crew error: $e');
    }
  }

  Future<void> _deleteCrewMember(String crewId) async {
    try {
      await _sb.from('gig_crew').delete().eq('id', crewId);
      await _load();
    } catch (e) {
      debugPrint('Delete crew error: $e');
    }
  }

  String _roleLabel(String role) {
    const labels = {
      'skarp': 'Skarp',
      'bass': 'Bass',
      'danser': 'Danser',
      'annet': 'Annet',
    };
    return labels[role] ?? role;
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
            child: const Text('Cancel'),
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
                    SnackBar(content: Text('Sending failed: $e')),
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
              const Text('Gig not found'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/m/gigs'),
                child: const Text('Back to Gigs'),
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
                      title.isNotEmpty ? title : (dateLabel.isNotEmpty ? dateLabel : 'Gig'),
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
                    if (customerLine.isNotEmpty && gigType != 'rehearsal')
                      Text(
                        customerLine,
                        style: const TextStyle(
                          color: CssTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (gigType == 'rehearsal') ...[
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
              _GigStatusBadge(status: status),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'edit') _editGigInfo();
                  if (v == 'delete') _confirmDeleteGig();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Rediger'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Slett gig', style: TextStyle(color: Colors.red)),
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
                    Tab(text: 'Shows & Pris'),
                    Tab(text: 'Crew'),
                    Tab(text: 'Kontrakt'),
                  ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: _gig?['type'] == 'rehearsal'
                  ? [
                      _InfoTab(gig: _gig!),
                    ]
                  : [
                      _InfoTab(gig: _gig!),
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
                      _CrewTab(
                        crew: _crew,
                        onAdd: _addCrewMember,
                        onToggle: _toggleCrewConfirmed,
                        onDelete: _deleteCrewMember,
                        roleLabel: _roleLabel,
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
// HELPER EXTENSION
// ===========================================================================

extension _StringOrNull on String {
  String? get orNull => isEmpty ? null : this;
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 13,
          color: CssTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
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

    return SingleChildScrollView(
      child: Row(
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
                if (isGig)
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
                if (isGig) ...[
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
              ],
            ),
          ),
        ],
      ),
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
    return SingleChildScrollView(
      child: Column(
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
                label: const Text('Add show'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Shows table
          if (widget.shows.isEmpty)
            const Text('No shows added yet.',
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
      ),
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
              tooltip: 'Remove',
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

class _CrewTab extends StatelessWidget {
  final List<Map<String, dynamic>> crew;
  final VoidCallback onAdd;
  final Future<void> Function(String id, bool current) onToggle;
  final Future<void> Function(String id) onDelete;
  final String Function(String role) roleLabel;

  const _CrewTab({
    required this.crew,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final confirmed = crew.where((c) => c['confirmed'] == true).length;
    final total = crew.length;
    final progress = total > 0 ? confirmed / total : 0.0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + add button
          Row(
            children: [
              Text('Crew', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add member'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress
          if (total > 0) ...[
            Row(
              children: [
                Text(
                  '$confirmed / $total bekreftet',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: CssTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: CssTheme.surface2,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Crew list
          if (crew.isEmpty)
            const Text('No crew members yet.',
                style: TextStyle(color: CssTheme.textMuted))
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: CssTheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: crew.asMap().entries.map((entry) {
                  final i = entry.key;
                  final member = entry.value;
                  final isLast = i == crew.length - 1;
                  final isConfirmed = member['confirmed'] == true;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isConfirmed
                          ? Colors.green.withOpacity(0.05)
                          : null,
                      border: isLast
                          ? null
                          : const Border(
                              bottom:
                                  BorderSide(color: CssTheme.outline)),
                      borderRadius: isLast
                          ? const BorderRadius.vertical(
                              bottom: Radius.circular(12))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Checkbox
                        GestureDetector(
                          onTap: () => onToggle(
                              member['id'] as String, isConfirmed),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isConfirmed
                                  ? Colors.green
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isConfirmed
                                    ? Colors.green
                                    : CssTheme.outline,
                                width: 2,
                              ),
                            ),
                            child: isConfirmed
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Avatar
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: CssTheme.surface2,
                          child: Text(
                            (member['name'] as String? ?? '?')
                                .characters
                                .first
                                .toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member['name'] as String? ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              if (member['role'] != null)
                                Text(
                                  roleLabel(member['role'] as String),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: CssTheme.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Delete
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: Colors.grey,
                          onPressed: () =>
                              onDelete(member['id'] as String),
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
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
      'inquiry': 'Inquiry',
      'confirmed': 'Confirmed',
      'cancelled': 'Cancelled',
      'invoiced': 'Invoiced',
      'completed': 'Completed',
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
