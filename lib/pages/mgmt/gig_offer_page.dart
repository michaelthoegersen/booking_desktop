import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/brreg_service.dart';
import '../../services/google_routes_service.dart';
import '../../services/polyline_decoder.dart';
import '../../services/toll_service.dart';
import '../../services/tripletex_service.dart';
import '../../state/active_company.dart';
import '../../widgets/new_company_dialog.dart';

// ──────────────────────────────────────────────────────────────────────────────
// GIG OFFER PAGE — Combined gig edit + pristilbud for Complete
// ──────────────────────────────────────────────────────────────────────────────

class GigOfferPage extends StatefulWidget {
  final String? offerId;
  final String? gigId;

  const GigOfferPage({super.key, this.offerId, this.gigId});

  @override
  State<GigOfferPage> createState() => _GigOfferPageState();
}

class _GigOfferPageState extends State<GigOfferPage> {
  final _sb = Supabase.instance.client;
  final _nf = NumberFormat('#,##0', 'nb_NO');

  bool _loading = true;
  bool _saving = false;
  String? _offerId;
  String? _gigId;

  // ── Companies / contacts ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;
  List<Map<String, dynamic>> _contacts = [];
  Map<String, dynamic>? _selectedContact;
  bool _loadingCompanies = true;

  // ── Customer ──────────────────────────────────────────────────────────────
  final _firmaCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _orgNrCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _invoiceOnEhf = false;

  // ── Location ──────────────────────────────────────────────────────────────
  final _venueCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'NO');

  // ── Dates & status ────────────────────────────────────────────────────────
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _gigStatus = 'inquiry';
  DateTime? _invoicedAt;
  final _responsibleCtrl = TextEditingController();

  // ── Schedule ──────────────────────────────────────────────────────────────
  final _meetingTimeCtrl = TextEditingController();
  final _getInTimeCtrl = TextEditingController();
  final _rehearsalTimeCtrl = TextEditingController();
  final _performanceTimeCtrl = TextEditingController();
  final _getOutTimeCtrl = TextEditingController();
  final _meetingNotesCtrl = TextEditingController();

  // ── Stage ─────────────────────────────────────────────────────────────────
  final _stageShapeCtrl = TextEditingController();
  final _stageSizeCtrl = TextEditingController();
  final _stageNotesCtrl = TextEditingController();

  // ── Tech ──────────────────────────────────────────────────────────────────
  bool _playbackFromUs = true;

  // ── Notes ─────────────────────────────────────────────────────────────────
  final _showDescCtrl = TextEditingController();
  final _notesContractCtrl = TextEditingController();
  final _infoOrgCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ── Price parameters ──────────────────────────────────────────────────────
  double _creoFeeMinimum = 5500;
  double _extraShowFee = 1500;
  double _markupPct = 0.25;
  bool _inearIncluded = false;
  double _inearPrice = 7000;
  double _transportPrice = 0;
  final _transportPriceCtrl = TextEditingController(text: '0');
  int _transportKm = 0;
  double _transportPricePerKm = 3.50;
  bool _privatbilExpanded = false;

  // ── Transport route calculator ──────────────────────────────────────────
  final _transportFromCtrl = TextEditingController();
  final _transportToCtrl = TextEditingController();
  final _transportViaCtrl = TextEditingController();
  bool _routeLoading = false;
  int _routePersons = 1;
  bool _routeReturn = true;
  double _tollCost = 0;
  List<TollStation> _tollStations = [];

  // ── Shows ─────────────────────────────────────────────────────────────────
  List<_OfferShow> _shows = [];
  List<Map<String, dynamic>> _showTypes = [];

  // ── Calculated ────────────────────────────────────────────────────────────
  double _performerFees = 0;
  double _completeKonto = 0;
  double _completePct = 0;
  double _bookingHonorar = 0;
  double _bookingPct = 0;
  double _inearTotal = 0;
  double _transportTotal = 0;
  double _total = 0;
  int _totalPerformers = 0;
  int _totalAppearances = 0;

  // _offerStatus removed — use _gigStatus for both gig and offer
  int? _tripletexInvoiceId;
  bool _sendingToTripletex = false;

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    _offerId = widget.offerId;
    _gigId = widget.gigId;
    _load();
  }

  @override
  void dispose() {
    _firmaCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _orgNrCtrl.dispose();
    _addressCtrl.dispose();
    _venueCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _responsibleCtrl.dispose();
    _meetingTimeCtrl.dispose();
    _getInTimeCtrl.dispose();
    _rehearsalTimeCtrl.dispose();
    _performanceTimeCtrl.dispose();
    _getOutTimeCtrl.dispose();
    _meetingNotesCtrl.dispose();
    _stageShapeCtrl.dispose();
    _stageSizeCtrl.dispose();
    _stageNotesCtrl.dispose();
    _showDescCtrl.dispose();
    _notesContractCtrl.dispose();
    _infoOrgCtrl.dispose();
    _notesCtrl.dispose();
    _transportPriceCtrl.dispose();
    _transportFromCtrl.dispose();
    _transportToCtrl.dispose();
    _transportViaCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // LOAD
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final companyId = activeCompanyNotifier.value?.id;
      final types = await _sb
          .from('show_types')
          .select('*')
          .eq('company_id', companyId!)
          .eq('active', true)
          .order('sort_order');
      _showTypes = List<Map<String, dynamic>>.from(types);

      _loadCompanies();

      if (_offerId != null) {
        // Load existing offer
        final offer = await _sb
            .from('gig_offers')
            .select('*')
            .eq('id', _offerId!)
            .single();

        _gigId = offer['gig_id'] as String?;
        // Status is read from gig, not offer
        _creoFeeMinimum = _dbl(offer['creo_fee_minimum'], 5500);
        _extraShowFee = _dbl(offer['extra_show_fee'], 1500);
        _markupPct = _dbl(offer['markup_pct'], 0.25);
        _inearIncluded = offer['inear_included'] == true;
        _inearPrice = _dbl(offer['inear_price'], 7000);
        _transportKm = (offer['transport_km'] as num?)?.toInt() ?? 0;
        _transportPricePerKm = _dbl(offer['transport_price_per_km'], 3.50);
        // Use stored transport_price if available, otherwise calculate from km
        final storedPrice = offer['transport_price'];
        _transportPrice = storedPrice != null
            ? _dbl(storedPrice, 0)
            : _transportKm * _transportPricePerKm;
        _transportPriceCtrl.text = _nf.format(_transportPrice);
        _notesCtrl.text = offer['notes'] ?? '';
        if (offer['invoiced_at'] != null) {
          _invoicedAt = DateTime.tryParse(offer['invoiced_at'].toString());
        }
        _tripletexInvoiceId = (offer['tripletex_invoice_id'] as num?)?.toInt();

        // Load offer shows
        final rows = await _sb
            .from('gig_offer_shows')
            .select('*')
            .eq('offer_id', _offerId!)
            .order('sort_order');
        _shows = (rows as List)
            .map((r) => _OfferShow.fromMap(r as Map<String, dynamic>))
            .toList();
      }

      // If we have a gig (either from offer or directly), load gig fields
      if (_gigId != null) {
        final gig = await _sb
            .from('gigs')
            .select('*')
            .eq('id', _gigId!)
            .maybeSingle();
        if (gig != null) _applyGigFields(gig);

        // Load gig shows if we don't have offer shows yet
        if (_shows.isEmpty) {
          final gigShows = await _sb
              .from('gig_shows')
              .select('*')
              .eq('gig_id', _gigId!)
              .order('sort_order');
          _shows = (gigShows as List).map((s) {
            final m = s as Map<String, dynamic>;
            return _OfferShow(
              showTypeId: m['show_type_id'] as String?,
              showName: m['show_name'] as String? ?? '',
              drummers: (m['drummers'] as num?)?.toInt() ?? 0,
              dancers: (m['dancers'] as num?)?.toInt() ?? 0,
              others: (m['others'] as num?)?.toInt() ?? 0,
              selected: true,
              sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
              ekstrainnslag: m['ekstrainnslag'] as String? ?? '',
            );
          }).toList();
        }
      }

      // If no shows yet, seed from catalog
      if (_shows.isEmpty) {
        _shows = _showTypes.map((t) {
          return _OfferShow(
            showTypeId: t['id'] as String?,
            showName: t['name'] as String? ?? '',
            drummers: (t['drummers'] as num?)?.toInt() ?? 0,
            dancers: (t['dancers'] as num?)?.toInt() ?? 0,
            others: (t['others'] as num?)?.toInt() ?? 0,
            selected: false,
            sortOrder: (t['sort_order'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      }

      _recalc();
    } catch (e) {
      debugPrint('GigOfferPage load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyGigFields(Map<String, dynamic> gig) {
    _firmaCtrl.text = gig['customer_firma'] ?? '';
    _nameCtrl.text = gig['customer_name'] ?? '';
    _emailCtrl.text = gig['customer_email'] ?? '';
    _phoneCtrl.text = gig['customer_phone'] ?? '';
    _orgNrCtrl.text = gig['customer_org_nr'] ?? '';
    _addressCtrl.text = gig['customer_address'] ?? '';
    _invoiceOnEhf = gig['invoice_on_ehf'] == true;
    _venueCtrl.text = gig['venue_name'] ?? '';
    _cityCtrl.text = gig['city'] ?? '';
    _countryCtrl.text = gig['country'] ?? 'NO';
    _dateFrom = gig['date_from'] != null
        ? DateTime.tryParse(gig['date_from'])
        : null;
    _dateTo =
        gig['date_to'] != null ? DateTime.tryParse(gig['date_to']) : null;
    _gigStatus = gig['status'] as String? ?? 'inquiry';
    _responsibleCtrl.text = gig['responsible'] ?? '';
    _meetingTimeCtrl.text = gig['meeting_time'] ?? '';
    _getInTimeCtrl.text = gig['get_in_time'] ?? '';
    _rehearsalTimeCtrl.text = gig['rehearsal_time'] ?? '';
    _performanceTimeCtrl.text = gig['performance_time'] ?? '';
    _getOutTimeCtrl.text = gig['get_out_time'] ?? '';
    _meetingNotesCtrl.text = gig['meeting_notes'] ?? '';
    _stageShapeCtrl.text = gig['stage_shape'] ?? '';
    _stageSizeCtrl.text = gig['stage_size'] ?? '';
    _stageNotesCtrl.text = gig['stage_notes'] ?? '';
    _playbackFromUs = gig['playback_from_us'] != false;
    _showDescCtrl.text = gig['show_desc'] ?? '';
    _notesContractCtrl.text = gig['notes_for_contract'] ?? '';
    _infoOrgCtrl.text = gig['info_from_organizer'] ?? '';

    // Only override offer price params from gig if we don't have an offer yet
    if (_offerId == null) {
      _inearIncluded = gig['inear_from_us'] == true;
      _inearPrice = _dbl(gig['inear_price'], 7000);
      _transportPrice = _dbl(gig['transport_price'], 0);
      _transportPriceCtrl.text = _nf.format(_transportPrice);
      _transportKm = (gig['transport_km'] as num?)?.toInt() ?? 0;
      if (gig['transport_price'] != null && _transportKm > 0) {
        _transportPricePerKm =
            _dbl(gig['transport_price'], 0) / _transportKm;
      }
    }
  }

  double _dbl(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // COMPANIES / CONTACTS
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _loadCompanies({String? autoSelectId}) async {
    if (_companyId == null) return;
    try {
      final res = await _sb
          .from('companies')
          .select('id, name, org_nr, address, city, country, contacts!contacts_company_id_fkey(id, name, phone, email)')
          .eq('owner_company_id', _companyId!)
          .order('name');
      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _companies = list;
          _loadingCompanies = false;
        });
      }
      if (autoSelectId != null) {
        final match = list.where((c) => c['id'] == autoSelectId).firstOrNull;
        if (match != null) _applyCompany(match);
      }
    } catch (e) {
      debugPrint('Load companies error: $e');
      if (mounted) setState(() => _loadingCompanies = false);
    }
  }

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
        _nameCtrl.text = contacts.first['name'] as String? ?? '';
        _phoneCtrl.text = contacts.first['phone'] as String? ?? '';
        _emailCtrl.text = contacts.first['email'] as String? ?? '';
      } else {
        _selectedContact = null;
        _nameCtrl.clear();
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
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
    });
  }

  void _applyContact(Map<String, dynamic> contact) {
    setState(() {
      _selectedContact = contact;
      _nameCtrl.text = contact['name'] as String? ?? '';
      _phoneCtrl.text = contact['phone'] as String? ?? '';
      _emailCtrl.text = contact['email'] as String? ?? '';
    });
  }

  Future<void> _openNewCompany() async {
    if (_companyId == null) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewCompanyDialog(ownerCompanyId: _companyId!),
    );
    if (result != null) {
      await _loadCompanies(autoSelectId: result);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // TRANSPORT ROUTE LOOKUP
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _lookupRoute() async {
    final from = _transportFromCtrl.text.trim();
    final to = _transportToCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn fra og til')),
      );
      return;
    }

    setState(() => _routeLoading = true);
    try {
      final places = <String>[from];
      final via = _transportViaCtrl.text.trim();
      if (via.isNotEmpty) {
        places.addAll(
            via.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
      }
      places.add(to);

      // Start toll loading in background (don't block route)
      TollService.loadStations().catchError((e) {
        debugPrint('Toll station load error: $e');
        return <TollStation>[];
      });

      final svc = GoogleRoutesService();
      final result = await svc.getRouteWithVia(places: places);

      final routes = result['routes'] as List<dynamic>? ?? [];
      if (routes.isNotEmpty) {
        final route = routes.first as Map<String, dynamic>;
        final distMeters = route['distanceMeters'] as num? ?? 0;
        final km = (distMeters / 1000).round();

        // Calculate tolls from polyline (if stations are loaded)
        final polyline = route['polyline'] as String?;
        List<TollStation> tollHits = [];
        if (polyline != null && polyline.isNotEmpty) {
          // Wait for toll stations with a timeout
          try {
            await TollService.loadStations()
                .timeout(const Duration(seconds: 10));
          } catch (_) {
            debugPrint('Toll stations timeout — skipping tolls');
          }
          final points = PolylineDecoder.decode(polyline);
          final routeCoords = points.map((p) => [p.lat, p.lng]).toList();
          final tollResult = TollService.calculateTolls(routeCoords);
          tollHits = tollResult.passedStations;
        }

        if (mounted) {
          setState(() {
            _transportKm = km * _routePersons * (_routeReturn ? 2 : 1);
            _tollStations = tollHits;
            _recalc();
            _syncTransportFromPrivatbil();
          });
        }
      }
    } catch (e) {
      debugPrint('Route lookup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved ruteoppslag: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // CALCULATION ENGINE
  // ────────────────────────────────────────────────────────────────────────────

  void _recalc() {
    final selected = _shows.where((s) => s.selected).toList();

    // Calculate performer fees from selected shows (can be 0)
    int maxDrummers = 0, maxDancers = 0, maxOthers = 0;
    int sumDrummers = 0, sumDancers = 0, sumOthers = 0;

    for (final s in selected) {
      maxDrummers = max(maxDrummers, s.drummers);
      maxDancers = max(maxDancers, s.dancers);
      maxOthers = max(maxOthers, s.others);
      sumDrummers += s.drummers;
      sumDancers += s.dancers;
      sumOthers += s.others;
    }

    _totalPerformers = maxDrummers + maxDancers + maxOthers;
    _totalAppearances = sumDrummers + sumDancers + sumOthers;

    final firstShowFees = _totalPerformers * _creoFeeMinimum;
    final extraShowFees =
        (_totalAppearances - _totalPerformers) * _extraShowFee;
    _performerFees = firstShowFees + extraShowFees;

    _inearTotal = _inearIncluded ? _inearPrice : 0;
    // Privatbil sub-values (for display only)
    _transportTotal = _transportKm * _transportPricePerKm;
    final tollMultiplier = _routePersons * (_routeReturn ? 2 : 1);
    final tollBase = _tollStations.fold<double>(0, (s, t) => s + t.priceCar);
    _tollCost = tollBase * tollMultiplier;

    // Markup is only applied to show/performer fees
    _completePct = _markupPct / 2;
    _bookingPct = _markupPct / 2;
    _completeKonto = _performerFees * _completePct;
    _bookingHonorar = _performerFees * _bookingPct;

    _total = _performerFees + _completeKonto + _bookingHonorar +
        _inearTotal + _transportPrice;
  }

  /// Update _transportPrice from privatbil calculator values
  void _syncTransportFromPrivatbil() {
    _transportPrice = _transportTotal + _tollCost;
    _transportPriceCtrl.text = _nf.format(_transportPrice);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SAVE — both gig and gig_offer
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_companyId == null) return;
    if (_dateFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg en dato først')),
      );
      return;
    }

    final isNew = _offerId == null;
    setState(() => _saving = true);
    try {
      String? n(String s) => s.trim().isEmpty ? null : s.trim();
      final now = DateTime.now().toIso8601String();
      final df = DateFormat('yyyy-MM-dd');

      _recalc();

      final gigData = {
        'company_id': _companyId,
        'type': 'gig',
        'date_from': df.format(_dateFrom!),
        'date_to': _dateTo != null ? df.format(_dateTo!) : null,
        'status': _gigStatus,
        'venue_name': n(_venueCtrl.text),
        'city': n(_cityCtrl.text),
        'country': n(_countryCtrl.text),
        'customer_firma': n(_firmaCtrl.text),
        'customer_name': n(_nameCtrl.text),
        'customer_email': n(_emailCtrl.text),
        'customer_phone': n(_phoneCtrl.text),
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
        'inear_from_us': _inearIncluded,
        'inear_price': _inearIncluded ? _inearPrice : null,
        'playback_from_us': _playbackFromUs,
        'transport_km': _transportKm,
        'transport_price': _transportPrice > 0 ? _transportPrice : null,
        'extra_desc': (_completeKonto + _bookingHonorar) > 0
            ? 'Complete + Bookinghonorar'
            : null,
        'extra_price': (_completeKonto + _bookingHonorar) > 0
            ? _completeKonto + _bookingHonorar
            : null,
        'notes_for_contract': n(_notesContractCtrl.text),
        'info_from_organizer': n(_infoOrgCtrl.text),
        'updated_at': now,
      };

      // ── 1. Create or update the gig ───────────────────────────────────────
      if (_gigId != null) {
        await _sb.from('gigs').update(gigData).eq('id', _gigId!);
      } else {
        gigData['created_by'] = _sb.auth.currentUser?.id;
        gigData['created_at'] = now;
        final gigRes =
            await _sb.from('gigs').insert(gigData).select('id').single();
        _gigId = gigRes['id'] as String;

        // Notify crew about the new gig
        try {
          final venue = n(_venueCtrl.text) ?? '';
          final notifyRes = await _sb.functions.invoke('notify-company', body: {
            'company_id': _companyId,
            'title': 'Ny gig: $venue',
            'body': '${_dateFrom != null ? DateFormat('dd.MM.yyyy').format(_dateFrom!) : ''} — $venue',
            'exclude_user_id': _sb.auth.currentUser?.id,
            'gig_id': _gigId,
          });
          debugPrint('notify-company response: status=${notifyRes.status} data=${notifyRes.data}');
        } catch (e) {
          debugPrint('notify-company error: $e');
        }
      }

      // ── 2. Sync gig_shows ─────────────────────────────────────────────────
      await _sb.from('gig_shows').delete().eq('gig_id', _gigId!);
      final selectedShows = _shows.where((s) => s.selected).toList();
      if (selectedShows.isNotEmpty) {
        final gigShowRows = selectedShows.asMap().entries.map((e) {
          final s = e.value;
          final showPerf = s.drummers + s.dancers + s.others;
          final isEkstra = s.showName.toLowerCase().contains('ekstrainnslag');
          final showPrice = isEkstra
              ? showPerf * _extraShowFee
              : showPerf * _creoFeeMinimum;
          return {
            'gig_id': _gigId,
            'show_type_id': s.showTypeId,
            'show_name': s.showName,
            'drummers': s.drummers,
            'dancers': s.dancers,
            'others': s.others,
            'price': showPrice.round(),
            'sort_order': e.key,
            'ekstrainnslag': s.ekstrainnslag.isNotEmpty ? s.ekstrainnslag : null,
          };
        }).toList();
        await _sb.from('gig_shows').insert(gigShowRows);
      }

      // ── 3. Save gig_offer ─────────────────────────────────────────────────
      final offerData = {
        'company_id': _companyId,
        'gig_id': _gigId,
        'customer_firma': n(_firmaCtrl.text),
        'customer_name': n(_nameCtrl.text),
        'customer_email': n(_emailCtrl.text),
        'customer_phone': n(_phoneCtrl.text),
        'customer_org_nr': n(_orgNrCtrl.text),
        'customer_address': n(_addressCtrl.text),
        'creo_fee_minimum': _creoFeeMinimum,
        'extra_show_fee': _extraShowFee,
        'markup_pct': _markupPct,
        'inear_included': _inearIncluded,
        'inear_price': _inearPrice,
        'transport_km': _transportKm,
        'transport_price_per_km': _transportPricePerKm,
        'transport_price': _transportPrice > 0 ? _transportPrice : null,
        'status': _gigStatus,
        'notes': n(_notesCtrl.text),
        'updated_at': now,
      };

      // Set invoiced_at when status changes to 'invoiced' for the first time
      if (_gigStatus == 'invoiced' && _invoicedAt == null) {
        final ts = DateTime.now().toUtc().toIso8601String();
        offerData['invoiced_at'] = ts;
        _invoicedAt = DateTime.now().toUtc();
        debugPrint('>>> invoiced_at SET to $ts for offer $_offerId');
      }

      if (_offerId != null) {
        await _sb.from('gig_offers').update(offerData).eq('id', _offerId!);
      } else {
        offerData['created_by'] = _sb.auth.currentUser?.id;
        offerData['created_at'] = now;
        final res = await _sb
            .from('gig_offers')
            .insert(offerData)
            .select('id')
            .single();
        _offerId = res['id'] as String;
      }

      // ── 4. Sync gig_offer_shows ───────────────────────────────────────────
      await _sb.from('gig_offer_shows').delete().eq('offer_id', _offerId!);
      if (_shows.isNotEmpty) {
        final showRows = _shows.asMap().entries.map((e) {
          final s = e.value;
          return {
            'offer_id': _offerId,
            'show_type_id': s.showTypeId,
            'show_name': s.showName,
            'drummers': s.drummers,
            'dancers': s.dancers,
            'others': s.others,
            'selected': s.selected,
            'sort_order': e.key,
            'ekstrainnslag': s.ekstrainnslag.isNotEmpty ? s.ekstrainnslag : null,
          };
        }).toList();
        await _sb.from('gig_offer_shows').insert(showRows);
      }

      // ── 5. Auto-save contact person ─────────────────────────────────────────
      if (_selectedCompany != null && n(_nameCtrl.text) != null) {
        try {
          final companyId = _selectedCompany!['id'] as String;
          final contactName = _nameCtrl.text.trim();
          final contactPhone = n(_phoneCtrl.text);
          final contactEmail = n(_emailCtrl.text);

          final existing = await _sb
              .from('contacts')
              .select('id, name, phone, email')
              .eq('company_id', companyId)
              .ilike('name', contactName)
              .maybeSingle();

          if (existing == null) {
            await _sb.from('contacts').insert({
              'company_id': companyId,
              'name': contactName,
              'phone': contactPhone,
              'email': contactEmail,
            });
          } else {
            final changed = existing['phone'] != contactPhone ||
                existing['email'] != contactEmail;
            if (changed) {
              await _sb.from('contacts').update({
                'phone': contactPhone,
                'email': contactEmail,
              }).eq('id', existing['id']);
            }
          }
        } catch (e) {
          debugPrint('Auto-save contact error: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
        );
        // If this was a new offer, navigate to the gig detail page
        if (isNew && _gigId != null) {
          context.go('/m/gigs/$_gigId');
        }
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved lagring: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ADD SHOW DIALOG
  // ────────────────────────────────────────────────────────────────────────────

  void _addShowDialog() {
    final existing = _shows.map((s) => s.showTypeId).toSet();
    final available =
        _showTypes.where((t) => !existing.contains(t['id'])).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle show-typer er allerede lagt til')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Legg til show'),
        children: available.map((t) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _shows.add(_OfferShow(
                  showTypeId: t['id'] as String?,
                  showName: t['name'] as String? ?? '',
                  drummers: (t['drummers'] as num?)?.toInt() ?? 0,
                  dancers: (t['dancers'] as num?)?.toInt() ?? 0,
                  others: (t['others'] as num?)?.toInt() ?? 0,
                  selected: true,
                  sortOrder: _shows.length,
                ));
                _recalc();
              });
            },
            child: Text(t['name'] as String? ?? ''),
          );
        }).toList(),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back link
          GestureDetector(
            onTap: () => _gigId != null
                ? context.go('/m/gigs/$_gigId')
                : context.go('/m/offers'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  _gigId != null ? 'Tilbake til gig' : 'Tilbud',
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

          Text(
            _offerId != null ? 'Rediger gig / tilbud' : 'Ny gig / tilbud',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),

          // Two-panel layout
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT PANEL
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildDateLocationCard(),
                        const SizedBox(height: 14),
                        _buildCustomerCard(),
                        const SizedBox(height: 14),
                        _buildShowsCard(),
                        const SizedBox(height: 14),
                        _buildPriceParamsCard(),
                        const SizedBox(height: 14),
                        _buildScheduleCard(),
                        const SizedBox(height: 14),
                        _buildStageCard(),
                        const SizedBox(height: 14),
                        _buildNotesCard(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 18),

                // RIGHT PANEL
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildCalcCard(),
                        const SizedBox(height: 14),
                        _buildActionsCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // CARD HELPER
  // ────────────────────────────────────────────────────────────────────────────

  Widget _card({required String title, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _tf(TextEditingController ctrl, String label, {int? maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      minLines: maxLines == null ? 1 : null,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _row2(Widget a, Widget b) {
    return Row(children: [
      Expanded(child: a),
      const SizedBox(width: 8),
      Expanded(child: b),
    ]);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // DATO & STED
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildDateLocationCard() {
    final dfmt = DateFormat('dd.MM.yyyy');
    return _card(
      title: 'Dato & sted',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_dateFrom != null
                      ? dfmt.format(_dateFrom!)
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
                  label: Text(
                      _dateTo != null ? dfmt.format(_dateTo!) : 'Dato til'),
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
            ],
          ),
          const SizedBox(height: 8),
          _tf(_performanceTimeCtrl, 'Tidspunkt'),
          const SizedBox(height: 8),
          _row2(
            DropdownButtonFormField<String>(
              value: _gigStatus,
              decoration: const InputDecoration(
                  labelText: 'Status', isDense: true),
              items: ['inquiry', 'confirmed', 'invoiced', 'completed', 'cancelled']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _gigStatus = v);
              },
            ),
            _tf(_responsibleCtrl, 'Ansvarlig'),
          ),
          const SizedBox(height: 8),
          _tf(_venueCtrl, 'Venue'),
          const SizedBox(height: 8),
          _row2(_tf(_cityCtrl, 'By'), _tf(_countryCtrl, 'Land')),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // KUNDE
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildCustomerCard() {
    return _card(
      title: 'Kunde',
      child: Column(
        children: [
          _CustomerPicker(
            companies: _companies,
            selectedCompany: _selectedCompany,
            loading: _loadingCompanies,
            onSelected: _applyCompany,
            onClear: _clearCompany,
            onNewCompany: _openNewCompany,
            ownerCompanyId: _companyId,
          ),
          if (_contacts.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedContact,
              decoration:
                  const InputDecoration(labelText: 'Velg kontaktperson'),
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
          const SizedBox(height: 12),
          _row2(_tf(_firmaCtrl, 'Firma'), _tf(_orgNrCtrl, 'Org.nr')),
          const SizedBox(height: 8),
          _row2(
              _tf(_nameCtrl, 'Kontaktperson'), _tf(_phoneCtrl, 'Telefon')),
          const SizedBox(height: 8),
          _row2(_tf(_emailCtrl, 'E-post'), _tf(_addressCtrl, 'Adresse')),
          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Faktura på EHF',
                style: TextStyle(fontSize: 13)),
            value: _invoiceOnEhf,
            onChanged: (v) => setState(() => _invoiceOnEhf = v),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SHOWS
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildShowsCard() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      title: 'Shows',
      child: Column(
        children: [
          _tf(_showDescCtrl, 'Showbeskrivelse', maxLines: 2),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Expanded(
                    child: Text('Show',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant))),
                SizedBox(
                    width: 50,
                    child: Text('T',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant))),
                SizedBox(
                    width: 50,
                    child: Text('D',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant))),
                SizedBox(
                    width: 50,
                    child: Text('A',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant))),
                const SizedBox(width: 36),
              ],
            ),
          ),
          ..._shows.asMap().entries.map((e) => _showRow(e.key, e.value)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addShowDialog,
              icon: const Icon(Icons.add, size: 16),
              label:
                  const Text('Legg til show', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _showRow(int index, _OfferShow s) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: s.selected,
                  onChanged: (v) {
                    setState(() {
                      _shows[index].selected = v ?? false;
                      _recalc();
                    });
                  },
                ),
              ),
              Expanded(
                child: Text(s.showName,
                    style: TextStyle(
                      fontSize: 13,
                      color: s.selected ? cs.onSurface : cs.onSurfaceVariant,
                      fontWeight:
                          s.selected ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),
              _miniNumberField(
                key: ValueKey('show_${index}_d'),
                value: s.drummers,
                onChanged: (v) {
                  _shows[index].drummers = v;
                  setState(() => _recalc());
                },
              ),
              _miniNumberField(
                key: ValueKey('show_${index}_da'),
                value: s.dancers,
                onChanged: (v) {
                  _shows[index].dancers = v;
                  setState(() => _recalc());
                },
              ),
              _miniNumberField(
                key: ValueKey('show_${index}_o'),
                value: s.others,
                onChanged: (v) {
                  _shows[index].others = v;
                  setState(() => _recalc());
                },
              ),
              SizedBox(
                width: 36,
                child: IconButton(
                  icon: Icon(Icons.close,
                      size: 16, color: cs.onSurfaceVariant),
                  onPressed: () {
                    setState(() {
                      _shows.removeAt(index);
                      _recalc();
                    });
                  },
                ),
              ),
            ],
          ),
          if (s.selected && s.showName.toLowerCase().contains('ekstrainnslag'))
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 8),
              child: TextField(
                key: ValueKey('show_${index}_ekstra'),
                controller: TextEditingController(text: s.ekstrainnslag),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Beskrivelse',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (v) => _shows[index].ekstrainnslag = v,
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniNumberField({
    required Key key,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 50,
      child: TextFormField(
        key: key,
        initialValue: '$value',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // PRISPARAMETRE
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildPriceParamsCard() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      title: 'Prisparametre',
      child: Column(
        children: [
          _paramRow('Creo-hyre min.', _creoFeeMinimum, (v) {
            _creoFeeMinimum = v;
            setState(() => _recalc());
          }),
          _paramRow('Tillegg pr. show', _extraShowFee, (v) {
            _extraShowFee = v;
            setState(() => _recalc());
          }),
          _paramRowPct('Påslag', _markupPct, (v) {
            _markupPct = v;
            setState(() => _recalc());
          }),
          // In-ear
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Row(
                    children: [
                      Text('In-Ear',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _inearIncluded,
                          onChanged: (v) {
                            setState(() {
                              _inearIncluded = v ?? false;
                              _recalc();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    key: const ValueKey('param_inear_price'),
                    initialValue: _nf.format(_inearPrice),
                    style: const TextStyle(fontSize: 13),
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(
                          v.replaceAll(RegExp(r'[^0-9.]'), ''));
                      if (parsed != null) {
                        _inearPrice = parsed;
                        setState(() => _recalc());
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Transport price ──
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text('Transport',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _transportPriceCtrl,
                    style: const TextStyle(fontSize: 13),
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(
                          v.replaceAll(RegExp(r'[^0-9.]'), ''));
                      if (parsed != null) {
                        _transportPrice = parsed;
                        setState(() => _recalc());
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Transport (Privatbil) — collapsible ──
          const Divider(height: 20),
          GestureDetector(
            onTap: () => setState(() => _privatbilExpanded = !_privatbilExpanded),
            child: Row(
              children: [
                Icon(
                  _privatbilExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text('Transport (privatbil)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ],
            ),
          ),
          if (_privatbilExpanded) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _transportFromCtrl,
            decoration: const InputDecoration(
              labelText: 'Fra',
              prefixIcon: Icon(Icons.trip_origin, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _transportViaCtrl,
            decoration: const InputDecoration(
              labelText: 'Via (kommaseparert)',
              prefixIcon: Icon(Icons.more_horiz, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _transportToCtrl,
            decoration: const InputDecoration(
              labelText: 'Til',
              prefixIcon: Icon(Icons.location_on, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Antall:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextFormField(
                  key: ValueKey('route_persons_$_routePersons'),
                  initialValue: '$_routePersons',
                  decoration: const InputDecoration(isDense: true),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _routePersons = parsed;
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _routeReturn = !_routeReturn),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _routeReturn ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    const Text('Tur/retur', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _routeLoading ? null : _lookupRoute,
                icon: _routeLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.route, size: 18),
                label: const Text('Beregn rute'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text('Km totalt',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    key: ValueKey('transport_km_$_transportKm'),
                    initialValue: '$_transportKm',
                    style: const TextStyle(fontSize: 13),
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(
                          v.replaceAll(RegExp(r'[^0-9]'), ''));
                      if (parsed != null) {
                        _transportKm = parsed;
                        _recalc();
                        _syncTransportFromPrivatbil();
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // Rate selector
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Kr/km', style: TextStyle(fontSize: 13)),
                ),
                _rateChip('3,50', 3.50),
                const SizedBox(width: 4),
                _rateChip('5,30', 5.30),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    key: ValueKey('kr_km_${_transportPricePerKm.toStringAsFixed(2)}'),
                    initialValue: _transportPricePerKm % 1 == 0
                        ? _transportPricePerKm.toInt().toString()
                        : _transportPricePerKm.toStringAsFixed(2),
                    decoration: const InputDecoration(isDense: true),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    onChanged: (v) {
                      final parsed = double.tryParse(
                          v.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''));
                      if (parsed != null) {
                        _transportPricePerKm = parsed;
                        _recalc();
                        _syncTransportFromPrivatbil();
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          ],
          // Playback toggle
          SwitchListTile(
            title: const Text('Playback fra oss',
                style: TextStyle(fontSize: 13)),
            value: _playbackFromUs,
            onChanged: (v) => setState(() => _playbackFromUs = v),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }

  Widget _rateChip(String label, double rate) {
    final cs = Theme.of(context).colorScheme;
    final selected = (_transportPricePerKm - rate).abs() < 0.01;
    return GestureDetector(
      onTap: () {
        _transportPricePerKm = rate;
        _recalc();
        _syncTransportFromPrivatbil();
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? Colors.black : cs.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _paramRow(
      String label, double value, ValueChanged<double> onChanged,
      {bool integer = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('param_$label'),
              initialValue:
                  integer ? '${value.round()}' : _nf.format(value),
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (v) {
                final parsed =
                    double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramRowPct(
      String label, double value, ValueChanged<double> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('param_$label'),
              initialValue: '${(value * 100).round()} %',
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (v) {
                final num = double.tryParse(
                    v.replaceAll('%', '').replaceAll(' ', '').trim());
                if (num != null) onChanged(num / 100);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // TIDSPLAN
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildScheduleCard() {
    return _card(
      title: 'Tidsplan',
      child: Column(
        children: [
          _tf(_meetingTimeCtrl, 'Oppmøte', maxLines: null),
          const SizedBox(height: 8),
          _tf(_getInTimeCtrl, 'Get-in', maxLines: null),
          const SizedBox(height: 8),
          _tf(_rehearsalTimeCtrl, 'Prøver', maxLines: null),
          const SizedBox(height: 8),
          _tf(_performanceTimeCtrl, 'Opptreden', maxLines: null),
          const SizedBox(height: 8),
          _tf(_getOutTimeCtrl, 'Get-out', maxLines: null),
          const SizedBox(height: 8),
          _tf(_meetingNotesCtrl, 'Oppmøtenotat', maxLines: null),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SCENE
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildStageCard() {
    return _card(
      title: 'Scene',
      child: Column(
        children: [
          _row2(
            _tf(_stageShapeCtrl, 'Sceneform'),
            _tf(_stageSizeCtrl, 'Scenestørrelse'),
          ),
          const SizedBox(height: 8),
          _tf(_stageNotesCtrl, 'Scenenotater', maxLines: 2),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // NOTATER
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildNotesCard() {
    return _card(
      title: 'Notater',
      child: Column(
        children: [
          _tf(_notesContractCtrl, 'Notater for kontrakt', maxLines: 3),
          const SizedBox(height: 8),
          _tf(_infoOrgCtrl, 'Info fra arrangør', maxLines: 3),
          const SizedBox(height: 8),
          _tf(_notesCtrl, 'Interne notater (tilbud)', maxLines: 3),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BEREGNING (RIGHT)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildCalcCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Beregning',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 14),
          _calcRow(
              'Antall show', '${_shows.where((s) => s.selected).length}'),
          _calcRow('Utøvere', '$_totalPerformers'),
          _calcRow('Opptredener', '$_totalAppearances'),
          const Divider(height: 24),
          _calcRow('Utøverhyrer', _nf.format(_performerFees)),
          _calcRowWithPct('CompleteKonto', _nf.format(_completeKonto), _completePct),
          _calcRowWithPct('BookingHonorar', _nf.format(_bookingHonorar), _bookingPct),
          _calcRow(
              'In-Ear', _inearIncluded ? _nf.format(_inearTotal) : '–'),
          _calcRow('Transport',
              _transportPrice > 0 ? _nf.format(_transportPrice) : '–'),
          if (_privatbilExpanded && _tollStations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_tollStations.length} bom × ${_routePersons * (_routeReturn ? 2 : 1)}',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TILBUD',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              Text('${_nf.format(_total)} kr',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _calcRowWithPct(String label, String value, double pct) {
    final cs = Theme.of(context).colorScheme;
    final pctStr = '${(pct * 100).toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text(pctStr,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant)),
            ],
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SEND TO TRIPLETEX
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _sendToTripletex() async {
    if (_companyId == null || _offerId == null) return;

    // ── Step 1: Build preview data (no API calls that create anything) ──
    _recalc();

    final customerName = _firmaCtrl.text.trim();
    if (customerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn kundenavn først')),
      );
      return;
    }

    final selectedShows = _shows.where((s) => s.selected).toList();
    final previewLines = <Map<String, dynamic>>[];

    if (selectedShows.isNotEmpty && _totalPerformers > 0) {
      for (final show in selectedShows) {
        final performers = show.drummers + show.dancers + show.others;
        if (performers <= 0) continue;
        final showFee = (_performerFees * performers / _totalPerformers);
        previewLines.add({
          'description': show.showName,
          'amount': showFee.roundToDouble(),
        });
      }
    }

    if (_transportPrice > 0) {
      previewLines.add({
        'description': 'Transport',
        'amount': _transportPrice.roundToDouble(),
      });
    }

    if (_inearIncluded && _inearTotal > 0) {
      previewLines.add({
        'description': 'In-ear monitors',
        'amount': _inearTotal.roundToDouble(),
      });
    }

    final markup = _completeKonto + _bookingHonorar;
    if (markup > 0) {
      previewLines.add({
        'description': 'Honorar',
        'amount': markup.roundToDouble(),
      });
    }

    if (previewLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen fakturalinjer å sende')),
      );
      return;
    }

    final previewTotal = previewLines.fold<double>(
      0, (s, l) => s + (l['amount'] as double),
    );

    // ── Step 2: Show confirmation dialog ──
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekreft faktura til Tripletex'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kunde: $customerName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_orgNrCtrl.text.trim().isNotEmpty)
                Text('Org.nr: ${_orgNrCtrl.text.trim()}'),
              if (_emailCtrl.text.trim().isNotEmpty)
                Text('E-post: ${_emailCtrl.text.trim()}'),
              const SizedBox(height: 16),
              const Text('Fakturalinjer:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...previewLines.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(l['description'] as String)),
                        Text('${_nf.format(l['amount'])} kr'),
                      ],
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Totalt',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${_nf.format(previewTotal)} kr',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Sendes som ${_invoiceOnEhf ? 'EHF' : 'e-post'} via Tripletex.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send faktura'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ── Step 3: Actually send ──
    setState(() => _sendingToTripletex = true);
    try {
      // Find or create customer
      final customer = await TripletexService.findOrCreateCustomer(
        _companyId!,
        name: customerName,
        orgNr: _orgNrCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
      final customerId = (customer['id'] as num).toInt();
      final resolvedName = customer['name'] as String? ?? customerName;
      debugPrint('Resolved customer: id=$customerId name=$resolvedName');

      // Set invoiceSendMethod on the customer — EHF requires ELMA registration
      var sendMethod = _invoiceOnEhf ? 'EHF' : 'EMAIL';
      try {
        await TripletexService.updateCustomer(_companyId!, customerId, {
          'invoiceSendMethod': sendMethod,
        });
        debugPrint('Customer $customerId invoiceSendMethod set to $sendMethod');
      } catch (e) {
        if (sendMethod == 'EHF') {
          debugPrint('EHF not available for customer, falling back to EMAIL: $e');
          sendMethod = 'EMAIL';
          await TripletexService.updateCustomer(_companyId!, customerId, {
            'invoiceSendMethod': 'EMAIL',
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Kunden kan ikke motta EHF — sendes på e-post i stedet'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          rethrow;
        }
      }

      // Build order lines
      final orderLines = previewLines.map((l) => {
        'description': l['description'],
        'count': 1,
        'unitPriceExcludingVatCurrency': l['amount'],
      }).toList();

      // Create order
      final invoiceDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final order = await TripletexService.createOrder(_companyId!, {
        'customer': {'id': customerId},
        'orderDate': invoiceDate,
        'deliveryDate': invoiceDate,
        'invoicesDueIn': 14,
        'orderLines': orderLines,
      });

      final orderId = (order['id'] as num).toInt();
      debugPrint('Order created: $orderId');

      // Create invoice from order (without sending yet)
      final invoice = await TripletexService.invoiceOrder(
        _companyId!,
        orderId: orderId,
        invoiceDate: invoiceDate,
      );

      final tripletexId = (invoice['id'] as num?)?.toInt() ??
          (invoice['invoiceNumber'] as num?)?.toInt();

      // Explicitly send via the resolved method (EHF or EMAIL)
      if (tripletexId != null) {
        debugPrint('Sending invoice $tripletexId as $sendMethod');
        await TripletexService.sendInvoice(
          _companyId!,
          invoiceId: tripletexId,
          sendType: sendMethod,
          overrideEmail: sendMethod == 'EMAIL' ? _emailCtrl.text.trim() : null,
        );
      }

      // Save tripletex_invoice_id + set status to invoiced
      if (tripletexId != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        await _sb.from('gig_offers').update({
          'tripletex_invoice_id': tripletexId,
          'status': 'invoiced',
          if (_invoicedAt == null) 'invoiced_at': now,
        }).eq('id', _offerId!);
        if (_gigId != null) {
          await _sb.from('gigs').update({'status': 'invoiced'}).eq('id', _gigId!);
        }
        setState(() {
          _tripletexInvoiceId = tripletexId;
          _gigStatus = 'invoiced';
          _invoicedAt ??= DateTime.now().toUtc();
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Faktura opprettet og sendt (ID: $tripletexId)')),
        );
      }
    } catch (e) {
      debugPrint('Tripletex send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _sendingToTripletex = false);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // HANDLINGER (RIGHT)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildActionsCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Handlinger',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save, size: 18),
            label: const Text('Lagre'),
          ),
          if (_gigId != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/m/gigs/$_gigId'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Åpne gig'),
            ),
          ],
          // Tripletex invoice button
          if (_offerId != null &&
              (_gigStatus == 'confirmed' || _gigStatus == 'invoiced')) ...[
            const SizedBox(height: 12),
            if (_tripletexInvoiceId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Sendt til Tripletex (#$_tripletexInvoiceId)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _sendingToTripletex ? null : _sendToTripletex,
                icon: _sendingToTripletex
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 16),
                label: const Text('Send til Tripletex'),
              ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOMER PICKER
// ──────────────────────────────────────────────────────────────────────────────

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
                  Icon(Icons.business_outlined,
                      size: 18,
                      color: loading
                          ? cs.onSurfaceVariant
                          : Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: loading
                        ? Text('Laster kunder…',
                            style: TextStyle(color: cs.onSurfaceVariant))
                        : selected != null
                            ? Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      selected['name'] as String? ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  if ((selected['city'] as String?) !=
                                      null)
                                    Text(selected['city'] as String,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant)),
                                ],
                              )
                            : Text('Velg kunde…',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant)),
                  ),
                  if (selected != null)
                    IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Fjern kunde',
                        onPressed: onClear)
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

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOMER PICKER DIALOG
// ──────────────────────────────────────────────────────────────────────────────

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

  /// Create a company in DB from Brreg data and return it as the selection.
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
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                        Icons.business_outlined,
                                        size: 18),
                                    title: Text(
                                        c['name'] as String? ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    subtitle: (c['city'] as String?) !=
                                            null
                                        ? Text(c['city'] as String,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    cs.onSurfaceVariant))
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

// ──────────────────────────────────────────────────────────────────────────────
// MODEL
// ──────────────────────────────────────────────────────────────────────────────

class _OfferShow {
  String? id;
  String? showTypeId;
  String showName;
  int drummers;
  int dancers;
  int others;
  bool selected;
  int sortOrder;
  String ekstrainnslag;

  _OfferShow({
    this.id,
    this.showTypeId,
    required this.showName,
    this.drummers = 0,
    this.dancers = 0,
    this.others = 0,
    this.selected = true,
    this.sortOrder = 0,
    this.ekstrainnslag = '',
  });

  factory _OfferShow.fromMap(Map<String, dynamic> m) {
    return _OfferShow(
      id: m['id'] as String?,
      showTypeId: m['show_type_id'] as String?,
      showName: m['show_name'] as String? ?? '',
      drummers: (m['drummers'] as num?)?.toInt() ?? 0,
      dancers: (m['dancers'] as num?)?.toInt() ?? 0,
      others: (m['others'] as num?)?.toInt() ?? 0,
      selected: m['selected'] == true,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      ekstrainnslag: m['ekstrainnslag'] as String? ?? '',
    );
  }
}
