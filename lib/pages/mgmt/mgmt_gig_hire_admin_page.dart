import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/active_company.dart';
// ──────────────────────────────────────────────────────────────────────────────
// MGMT GIG HIRE ADMIN PAGE
// ──────────────────────────────────────────────────────────────────────────────

class MgmtGigHireAdminPage extends StatefulWidget {
  const MgmtGigHireAdminPage({super.key});

  @override
  State<MgmtGigHireAdminPage> createState() => _MgmtGigHireAdminPageState();
}

class _MgmtGigHireAdminPageState extends State<MgmtGigHireAdminPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('dd.MM.yyyy');

  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];

  /// Human-readable trace of what the loader actually found, shown in the
  /// UI so a wrong number can be diagnosed without a browser console.
  final List<String> _diag = [];
  String _filter = 'outstanding'; // 'outstanding' or 'archive'

  // Bank balance
  double? _bankBalance;
  String? _bankCurrency;
  DateTime? _bankUpdatedAt;
  bool _bankLoading = false;
  bool _bankConnected = false;

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
    _loadBankBalance();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    super.dispose();
  }

  void _onCompanyChanged() {
    _load();
    _loadBankBalance();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _diag.clear();
    try {
      if (_companyId == null) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      // 1. Gigs for this company — only past/today (not future)
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final gigs = List<Map<String, dynamic>>.from(
        await _sb
            .from('gigs')
            .select('id, date_from, venue_name, customer_firma, type')
            .eq('company_id', _companyId!)
            .lte('date_from', todayStr),
      );
      if (gigs.isEmpty) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      final gigIds = gigs.map((g) => g['id'] as String).toList();
      final gigMap = {for (final g in gigs) g['id'] as String: g};

      // Fakturert/betalt for hyre som ikke har en lineup-rad (bookinghonorar
      // og frittstående ekstra). Nøkkel: gig|bruker|hyretype.
      final markMap = <String, Map<String, dynamic>>{};
      for (final m in List<Map<String, dynamic>>.from(
        await _sb
            .from('gig_hire_marks')
            .select('gig_id, user_id, section, crew_invoiced_at, crew_paid_at')
            .inFilter('gig_id', gigIds),
      )) {
        markMap['${m['gig_id']}|${m['user_id']}|${m['section']}'] = m;
      }

      // 2. Lineup entries for these gigs
      final lineup = List<Map<String, dynamic>>.from(
        await _sb
            .from('gig_lineup')
            .select('*')
            .inFilter('gig_id', gigIds),
      );
      if (lineup.isEmpty) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }

      // 3. Gig offers → fee info
      final offers = List<Map<String, dynamic>>.from(
        await _sb
            .from('gig_offers')
            .select('id, gig_id, creo_fee_minimum, extra_show_fee, final_calc, '
                'markup_pct, inear_included, inear_price, transport_price, '
                'rehearsal_performers, rehearsal_count, rehearsal_price_per_person, '
                'rehearsal_transport, markup_on_all, extras')
            .eq('company_id', _companyId!)
            .inFilter('gig_id', gigIds),
      );
      debugPrint('[GIG_HIRE] offers found: ${offers.length}, final_calcs: ${offers.where((o) => o['final_calc'] != null).length}');
      final offerByGig = <String, Map<String, dynamic>>{};
      for (final o in offers) {
        offerByGig[o['gig_id'] as String] = o;
      }

      // gig_offers.gig_id only ever points at the offer's FIRST date, and on
      // an offer with a rehearsal that first date is the rehearsal. Resolving
      // offers by that column alone therefore put the whole hire on the
      // rehearsal and left the actual show date without an offer at all — it
      // was skipped. The junction table is what maps an offer to every one of
      // its dates, exactly as the mobile app reads it.
      final missingGigIds =
          gigIds.where((id) => !offerByGig.containsKey(id)).toList();
      if (missingGigIds.isNotEmpty) {
        final junctionRows = List<Map<String, dynamic>>.from(
          await _sb
              .from('gig_offer_gigs')
              .select('offer_id, gig_id')
              .inFilter('gig_id', missingGigIds),
        );
        final junctionOfferIds = junctionRows
            .map((r) => r['offer_id'] as String)
            .toSet()
            .toList();
        if (junctionOfferIds.isNotEmpty) {
          final junctionOffers = List<Map<String, dynamic>>.from(
            await _sb
                .from('gig_offers')
                .select(
                    'id, gig_id, creo_fee_minimum, extra_show_fee, final_calc, '
                    'markup_pct, inear_included, inear_price, transport_price, '
                    'rehearsal_performers, rehearsal_count, rehearsal_price_per_person, '
                    'rehearsal_transport, markup_on_all, extras')
                .eq('company_id', _companyId!)
                .inFilter('id', junctionOfferIds),
          );
          final byOfferId = {
            for (final o in junctionOffers) o['id'] as String: o
          };
          for (final jr in junctionRows) {
            final gid = jr['gig_id'] as String;
            final oid = jr['offer_id'] as String;
            if (!offerByGig.containsKey(gid) && byOfferId.containsKey(oid)) {
              offerByGig[gid] = byOfferId[oid]!;
            }
          }
        }
      }

      // How many dates each offer covers — the booking honorar belongs to the
      // offer as a whole, so it is split across them rather than charged in
      // full on every date.
      _diag.add('Gigger (t.o.m. i dag): ${gigIds.length}');
      _diag.add('Tilbud funnet direkte: ${offers.length}');
      _diag.add('Gigger koblet til tilbud etter junction: '
          '${offerByGig.length}');


      // How many PERFORMANCE dates each offer covers. The booking honorar is
      // earned by landing the job, so it belongs on the dates that are shows —
      // never on a rehearsal. Splitting it across every date put part of it on
      // the rehearsal, where it has no business being.
      final offerShowDateCount = <String, int>{};
      final allOfferIds =
          offerByGig.values.map((o) => o['id'] as String).toSet().toList();
      if (allOfferIds.isNotEmpty) {
        final junction = List<Map<String, dynamic>>.from(
          await _sb
              .from('gig_offer_gigs')
              .select('offer_id, gig_id')
              .inFilter('offer_id', allOfferIds),
        );
        // Types for every date in those offers, including dates outside the
        // window this page loads, so the split adds up to the whole honorar.
        final junctionGigIds =
            junction.map((r) => r['gig_id'] as String).toSet().toList();
        final typeById = <String, String>{};
        if (junctionGigIds.isNotEmpty) {
          for (final g in List<Map<String, dynamic>>.from(
            await _sb
                .from('gigs')
                .select('id, type')
                .inFilter('id', junctionGigIds),
          )) {
            typeById[g['id'] as String] = g['type'] as String? ?? 'gig';
          }
        }
        for (final r in junction) {
          if (typeById[r['gig_id'] as String] == 'rehearsal') continue;
          final oid = r['offer_id'] as String;
          offerShowDateCount[oid] = (offerShowDateCount[oid] ?? 0) + 1;
        }
      }

      // 4. Group lineup by (gig_id, user_id) to count shows & collect lineup ids
      // Key = 'gigId|userId'
      final grouped = <String, Map<String, dynamic>>{};
      for (final l in lineup) {
        final gigId = l['gig_id'] as String;
        final userId = l['user_id'] as String;
        final key = '$gigId|$userId';
        if (!grouped.containsKey(key)) {
          grouped[key] = {
            'lineup_ids': <String>[l['id'] as String],
            'gig_id': gigId,
            'user_id': userId,
            'section': l['section'] ?? '',
            'show_ids': <String>{
              if (l['show_id'] != null) l['show_id'] as String
            },
            'crew_invoiced_at': l['crew_invoiced_at'],
            'crew_paid_at': l['crew_paid_at'],
          };
        } else {
          final g = grouped[key]!;
          (g['lineup_ids'] as List<String>).add(l['id'] as String);
          if (l['show_id'] != null) {
            (g['show_ids'] as Set<String>).add(l['show_id'] as String);
          }
          // Use the earliest non-null paid/invoiced timestamps
          g['crew_invoiced_at'] ??= l['crew_invoiced_at'];
          g['crew_paid_at'] ??= l['crew_paid_at'];
        }
      }

      // 5. Profiles → names
      final userIds =
          lineup.map((l) => l['user_id'] as String).toSet().toList();
      final profiles = List<Map<String, dynamic>>.from(
        await _sb
            .from('profiles')
            .select('id, name')
            .inFilter('id', userIds),
      );
      final nameMap = {
        for (final p in profiles) p['id'] as String: p['name'] as String? ?? ''
      };

      // 6. Fetch approved expenses per gig (personal expenses)
      final expenseRows = List<Map<String, dynamic>>.from(
        await _sb
            .from('expenses')
            .select('gig_id, user_id, amount, expense_type')
            .inFilter('gig_id', gigIds)
            .eq('status', 'approved'),
      );
      // Map: gigId|userId → total personal expenses
      final expenseMap = <String, double>{};
      // Map: gigId → total company card expenses
      final companyCardMap = <String, double>{};
      for (final e in expenseRows) {
        final type = e['expense_type'] as String? ?? 'receipt';
        if (type == 'company_card') {
          final gid = e['gig_id'] as String;
          companyCardMap[gid] = (companyCardMap[gid] ?? 0) +
              ((e['amount'] as num?)?.toDouble() ?? 0);
        } else {
          final key = '${e['gig_id']}|${e['user_id']}';
          expenseMap[key] = (expenseMap[key] ?? 0) +
              ((e['amount'] as num?)?.toDouble() ?? 0);
        }
      }

      // 7. Build entries — one per person per gig
      // Stian Skog always gets BookingHonorar
      const stianUserId = 'b1d06003-e856-4122-a747-301e4b7cd068';

      // Which offers have a non-rehearsal date that will actually produce hire
      // rows. A rehearsal is paid from the offer's separate Prøver parameters,
      // but only when a show date exists to carry the show hire — on an offer
      // where the rehearsal is the only date with a lineup, that row IS the
      // payout and repricing it to the rehearsal rate wipes real money.
      {
        final utenTilbud = <String>[];
        for (final g in grouped.values) {
          final gid = g['gig_id'] as String;
          if (offerByGig.containsKey(gid)) continue;
          final gg = gigMap[gid];
          final label = '${gg?['date_from'] ?? '?'} '
              '${gg?['venue_name'] ?? ''} (${gg?['type'] ?? '?'})';
          if (!utenTilbud.contains(label)) utenTilbud.add(label);
        }
        if (utenTilbud.isEmpty) {
          _diag.add('Gigger med lag, men uten tilbud: ingen');
        } else {
          _diag.add('Gigger med lag, men UTEN tilbud '
              '(hoppes over): ${utenTilbud.length}');
          for (final l in utenTilbud.take(15)) {
            _diag.add('   • $l');
          }
        }
      }

      final offerHasShowEntry = <String, bool>{};
      for (final g in grouped.values) {
        final gid = g['gig_id'] as String;
        final off = offerByGig[gid];
        if (off == null) continue;
        if ((gigMap[gid]?['type'] as String?) != 'rehearsal') {
          offerHasShowEntry[off['id'] as String] = true;
        }
      }

      final entries = <Map<String, dynamic>>[];
      // Track which gigs Stian is already in lineup for
      final stianGigs = <String>{};

      for (final g in grouped.values) {
        final gigId = g['gig_id'] as String;
        final userId = g['user_id'] as String;
        final gig = gigMap[gigId];
        final offer = offerByGig[gigId];
        if (offer == null) continue;

        if (userId == stianUserId) stianGigs.add(gigId);

        final creoFee =
            (offer['creo_fee_minimum'] as num?)?.toDouble() ?? 0.0;
        final extraShowFee =
            (offer['extra_show_fee'] as num?)?.toDouble() ?? 0.0;
        final numShows = (g['show_ids'] as Set<String>).length;
        final effectiveShows = numShows > 0 ? numShows : 1;
        final rehearsalFee =
            (offer['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0.0;
        final isRehearsal = (gig?['type'] as String?) == 'rehearsal';
        // Pay the rehearsal rate only when a show date of the same offer is
        // there to take the show hire. Otherwise this row is the whole job.
        final payAsRehearsal =
            isRehearsal && (offerHasShowEntry[offer['id'] as String] ?? false);
        double hireFee = payAsRehearsal
            ? rehearsalFee
            : creoFee +
                (effectiveShows > 1
                    ? extraShowFee * (effectiveShows - 1)
                    : 0);
        // Base show hire (before BookingHonorar) — used as the weight when an
        // extra cost is distributed to the group "same as show".
        final showHire = hireFee;

        // BookingHonorar belongs to the offer, so it is split across its dates.
        // BookingHonorar goes on the show dates, split between them. A row
        // paid as a rehearsal never carries any of it.
        if (userId == stianUserId && !payAsRehearsal) {
          final dates = offerShowDateCount[offer['id'] as String] ?? 1;
          hireFee += _getBookingHonorar(offer) / (dates > 0 ? dates : 1);
        }

        final expenseTotal = expenseMap['$gigId|$userId'] ?? 0.0;
        final amount = hireFee + expenseTotal;

        // Offer total stored per entry for use in grouped view
        double offerTotal = 0;
        final rawCalc = offer['final_calc'];
        if (rawCalc is Map && rawCalc['total'] != null) {
          offerTotal = (rawCalc['total'] as num).toDouble();
        }

        entries.add({
          'lineup_ids': g['lineup_ids'],
          'lineup_id': (g['lineup_ids'] as List<String>).first,
          'gig_id': gigId,
          'offer_id': offer['id'],
          'user_id': g['user_id'],
          'date_from': gig?['date_from'],
          'venue_name': gig?['venue_name'] ?? '',
          'customer_firma': gig?['customer_firma'] ?? '',
          'name': nameMap[g['user_id']] ?? '',
          'section': g['section'] ?? '',
          'is_rehearsal': payAsRehearsal,
          'num_shows': payAsRehearsal ? 0 : effectiveShows,
          'hire_fee': hireFee,
          'show_hire': showHire,
          'expense_total': expenseTotal,
          'amount': amount,
          'extra_total': 0.0,
          'offer_total': offerTotal,
          'offer': offer,
          'company_card_total': companyCardMap[gigId] ?? 0.0,
          'crew_invoiced_at': g['crew_invoiced_at'],
          'crew_paid_at': g['crew_paid_at'],
        });
      }

      // Add Stian's BookingHonorar for gigs where he's NOT in lineup
      for (final gigId in offerByGig.keys) {
        if (stianGigs.contains(gigId)) continue;
        final gig = gigMap[gigId];
        if (gig == null) continue;
        // A rehearsal date never carries the booking honorar.
        if ((gig['type'] as String?) == 'rehearsal') continue;
        final offer = offerByGig[gigId]!;
        final dates = offerShowDateCount[offer['id'] as String] ?? 1;
        final bookingHonorar =
            _getBookingHonorar(offer) / (dates > 0 ? dates : 1);
        if (bookingHonorar <= 0) continue;

        double offerTotal = 0;
        final rawCalc = offer['final_calc'];
        if (rawCalc is Map && rawCalc['total'] != null) {
          offerTotal = (rawCalc['total'] as num).toDouble();
        }

        entries.add({
          'lineup_ids': <String>[],
          'lineup_id': '',
          'gig_id': gigId,
          'offer_id': offer['id'],
          'user_id': stianUserId,
          'date_from': gig['date_from'],
          'venue_name': gig['venue_name'] ?? '',
          'customer_firma': gig['customer_firma'] ?? '',
          'name': nameMap[stianUserId] ?? 'Stian Skog',
          'section': 'booking',
          'num_shows': 0,
          'hire_fee': bookingHonorar,
          'show_hire': 0.0,
          'expense_total': 0.0,
          'amount': bookingHonorar,
          'extra_total': 0.0,
          'offer_total': offerTotal,
          'offer': offer,
          'crew_invoiced_at':
              markMap['$gigId|$stianUserId|booking']?['crew_invoiced_at'],
          'crew_paid_at':
              markMap['$gigId|$stianUserId|booking']?['crew_paid_at'],
        });
      }

      // ── Ekstrakostnader → gigghyre allocation ───────────────────────────
      // Each offer's extras are paid out ONCE, attached to the offer's first
      // show date (not a rehearsal). Allocation per extra:
      //   group         → distributed to that gig's lineup, weighted by
      //                    show hire
      //   member        → whole amount to the chosen member
      //   split         → member_amount to the member, remainder to the group
      //   company       → the whole amount stays with Complete (never paid out)
      //   split_company → member_amount to the member, remainder stays with
      //                   Complete (never paid out to the lineup)
      final offersById = <String, Map<String, dynamic>>{};
      final gigIdsByOffer = <String, List<String>>{};
      offerByGig.forEach((gid, off) {
        final oid = off['id'] as String;
        offersById[oid] = off;
        (gigIdsByOffer[oid] ??= <String>[]).add(gid);
      });

      for (final oid in offersById.keys) {
        final offer = offersById[oid]!;
        final extrasRaw = offer['extras'];
        if (extrasRaw is! List || extrasRaw.isEmpty) continue;

        // First show date for this offer (non-rehearsal, earliest date).
        final showGigs = (gigIdsByOffer[oid] ?? const <String>[])
            .map((gid) => gigMap[gid])
            .whereType<Map<String, dynamic>>()
            .where((g) => (g['type'] as String?) != 'rehearsal')
            .toList()
          ..sort((a, b) => (a['date_from'] as String? ?? '')
              .compareTo(b['date_from'] as String? ?? ''));
        if (showGigs.isEmpty) continue;
        final firstGigId = showGigs.first['id'] as String;

        // Tally group vs per-member portions across all extras.
        double groupTotal = 0;
        final memberExtras = <String, double>{};
        final memberNames = <String, String>{};
        for (final raw in extrasRaw) {
          if (raw is! Map) continue;
          final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
          if (amount <= 0) continue;
          final alloc = raw['allocation'] as String? ?? 'group';
          final memberId = raw['member_id'] as String?;
          double memberAmount;
          if (alloc == 'member' && memberId != null) {
            memberAmount = amount;
          } else if ((alloc == 'split' || alloc == 'split_company') &&
              memberId != null) {
            memberAmount = ((raw['member_amount'] as num?)?.toDouble() ?? 0)
                .clamp(0.0, amount);
          } else {
            memberAmount = 0;
          }
          // Whatever belongs to Complete is not distributed to the lineup:
          // all of it for 'company', the remainder for 'split_company'.
          if (alloc != 'split_company' && alloc != 'company') {
            groupTotal += amount - memberAmount;
          }
          if (memberAmount > 0 && memberId != null) {
            memberExtras[memberId] =
                (memberExtras[memberId] ?? 0) + memberAmount;
            final nm = raw['member_name'] as String?;
            if (nm != null && nm.isNotEmpty) memberNames[memberId] = nm;
          }
        }

        // Member rows on the first show gig.
        final gigEntries =
            entries.where((e) => e['gig_id'] == firstGigId).toList();

        // Distribute the group portion, weighted by each member's show hire.
        if (groupTotal > 0 && gigEntries.isNotEmpty) {
          double totalShowHire = 0;
          for (final e in gigEntries) {
            totalShowHire += (e['show_hire'] as num?)?.toDouble() ?? 0;
          }
          for (final e in gigEntries) {
            final w = (e['show_hire'] as num?)?.toDouble() ?? 0;
            final share = totalShowHire > 0
                ? groupTotal * (w / totalShowHire)
                : groupTotal / gigEntries.length;
            e['hire_fee'] = (e['hire_fee'] as num).toDouble() + share;
            e['amount'] = (e['amount'] as num).toDouble() + share;
            e['extra_total'] =
                ((e['extra_total'] as num?)?.toDouble() ?? 0) + share;
          }
        }

        // Apply per-member portions (added to the chosen member's gigghyre).
        memberExtras.forEach((memberId, extraAmt) {
          Map<String, dynamic>? target;
          for (final e in entries) {
            if (e['gig_id'] == firstGigId && e['user_id'] == memberId) {
              target = e;
              break;
            }
          }
          if (target != null) {
            target['hire_fee'] = (target['hire_fee'] as num).toDouble() + extraAmt;
            target['amount'] = (target['amount'] as num).toDouble() + extraAmt;
            target['extra_total'] =
                ((target['extra_total'] as num?)?.toDouble() ?? 0) + extraAmt;
          } else {
            // Member not in this gig's lineup — add a standalone payout row.
            final gig = gigMap[firstGigId];
            double offerTotal = 0;
            final rawCalc = offer['final_calc'];
            if (rawCalc is Map && rawCalc['total'] != null) {
              offerTotal = (rawCalc['total'] as num).toDouble();
            }
            entries.add({
              'lineup_ids': <String>[],
              'lineup_id': '',
              'gig_id': firstGigId,
              'offer_id': offer['id'],
              'user_id': memberId,
              'date_from': gig?['date_from'],
              'venue_name': gig?['venue_name'] ?? '',
              'customer_firma': gig?['customer_firma'] ?? '',
              'name': nameMap[memberId] ?? memberNames[memberId] ?? '',
              'section': 'ekstra',
              'num_shows': 0,
              'hire_fee': extraAmt,
              'show_hire': 0.0,
              'expense_total': 0.0,
              'amount': extraAmt,
              'extra_total': extraAmt,
              'offer_total': offerTotal,
              'offer': offer,
              'company_card_total': companyCardMap[firstGigId] ?? 0.0,
              'crew_invoiced_at':
                  markMap['$firstGigId|$memberId|ekstra']?['crew_invoiced_at'],
              'crew_paid_at':
                  markMap['$firstGigId|$memberId|ekstra']?['crew_paid_at'],
            });
          }
        });
      }

      // Hide a rehearsal row the offer pays nothing for — and ONLY that. An
      // earlier version dropped every zero row, which could silently remove a
      // gig's payout if anything upstream miscalculated it. A filter on money
      // must never be able to hide money, so this one cannot touch a show row
      // whatever the amount turns out to be.
      entries.removeWhere((e) =>
          e['is_rehearsal'] == true &&
          ((e['amount'] as num?)?.toDouble() ?? 0) <= 0);

      // Sort by date descending
      entries.sort((a, b) {
        final da = a['date_from'] as String? ?? '';
        final db = b['date_from'] as String? ?? '';
        return db.compareTo(da);
      });

      {
        final perGig = <String, List<Map<String, dynamic>>>{};
        for (final e in entries) {
          (perGig[e['gig_id'] as String] ??= []).add(e);
        }
        _diag.add('Rader bygget: ${entries.length} '
            'fordelt på ${perGig.length} gigger');
        final lines = <String>[];
        perGig.forEach((gid, rows) {
          final f = rows.first;
          final sum = rows.fold<double>(
              0, (a, e) => a + ((e['amount'] as num?)?.toDouble() ?? 0));
          lines.add('${f['date_from']} ${f['venue_name']} — '
              '${rows.length} rader, ${sum.round()} kr'
              '${f['is_rehearsal'] == true ? ' [prøve]' : ''}');
        });
        lines.sort();
        for (final l in lines.reversed.take(25)) {
          _diag.add('   • $l');
        }
      }

      _entries = entries;
    } catch (e, st) {
      debugPrint('Load gig hire error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved lasting av gigghyrer: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Bank balance ─────────────────────────────────────────────────────────
  Future<void> _loadBankBalance() async {
    if (_companyId == null) return;
    if (mounted) setState(() => _bankLoading = true);

    // First try cached balance from DB (fast, no edge function call)
    try {
      final row = await _sb
          .from('company_bank_accounts')
          .select('balance, currency, balance_updated_at')
          .eq('company_id', _companyId!)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (row != null) {
        _bankBalance = (row['balance'] as num?)?.toDouble();
        _bankCurrency = row['currency'] as String? ?? 'NOK';
        final updStr = row['balance_updated_at'] as String?;
        _bankUpdatedAt = updStr != null ? DateTime.tryParse(updStr) : null;
        _bankConnected = true;
      }
    } catch (_) {
      // Table might not exist yet — silently ignore
    }

    // Then try live balance from edge function (slower, but fresh)
    if (_bankConnected) {
      try {
        final res = await _sb.functions.invoke('bank-balance', body: {
          'company_id': _companyId,
        });
        final data = res.data;
        if (data is Map<String, dynamic> && data['accounts'] != null) {
          final accounts = data['accounts'] as List;
          if (accounts.isNotEmpty) {
            final first = accounts[0] as Map<String, dynamic>;
            _bankBalance = (first['balance'] as num?)?.toDouble();
            _bankCurrency = first['currency'] as String? ?? 'NOK';
            final updStr = first['updated_at'] as String?;
            _bankUpdatedAt = updStr != null ? DateTime.tryParse(updStr) : null;
          }
        }
      } catch (e) {
        debugPrint('Bank balance refresh error (using cached): $e');
      }
    }

    if (mounted) setState(() => _bankLoading = false);
  }

  Future<void> _connectBank() async {
    if (_companyId == null) return;
    try {
      final res = await _sb.functions.invoke('bank-connect-company', body: {
        'company_id': _companyId,
        'institution_id': 'DNB',
      });
      final data = res.data as Map<String, dynamic>?;
      final link = data?['link'] as String?;
      if (link != null) {
        await launchUrl(Uri.parse(link));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved banktilkobling: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'outstanding') {
      return _entries.where((e) => e['crew_paid_at'] == null).toList();
    }
    return _entries.where((e) => e['crew_paid_at'] != null).toList();
  }

  double get _totalOutstanding {
    return _entries
        .where((e) => e['crew_paid_at'] == null)
        .fold(0.0, (sum, e) => sum + (e['amount'] as double));
  }

  double _getBookingHonorar(Map<String, dynamic> offer) {
    final rawCalc = offer['final_calc'];
    if (rawCalc is Map) {
      final lines = rawCalc['lines'] as List?;
      if (lines != null) {
        for (final line in lines) {
          if ((line['label'] as String?)?.contains('BookingHonorar') == true) {
            return (line['amount'] as num?)?.toDouble() ?? 0;
          }
        }
      }
    }
    // Fallback: half of total markup
    final markupPct = (offer['markup_pct'] as num?)?.toDouble() ?? 0;
    if (markupPct > 0) {
      final creo = (offer['creo_fee_minimum'] as num?)?.toDouble() ?? 0;
      return creo * (markupPct / 2);
    }
    return 0;
  }

  /// Key identifying a hire row that has no lineup row of its own.
  static String _markKey(Map<String, dynamic> e) =>
      '${e['gig_id']}|${e['user_id']}|${e['section']}';

  /// Writes [field] for one hire row.
  ///
  /// Someone who stood in the lineup is marked on their gig_lineup row, as
  /// before. Booking honorar and a standalone ekstra have no lineup row, so
  /// those are marked in gig_hire_marks instead — otherwise the update matched
  /// nothing and the button did nothing without saying so.
  Future<void> _setMark(
      Map<String, dynamic> entry, String field, String? iso) async {
    final lineupIds = List<String>.from(entry['lineup_ids'] as List);

    if (lineupIds.isNotEmpty) {
      await _sb
          .from('gig_lineup')
          .update({field: iso})
          .inFilter('id', lineupIds);
      _updateLocalEntries(lineupIds, field, iso);
      return;
    }

    await _sb.from('gig_hire_marks').upsert({
      'company_id': _companyId,
      'gig_id': entry['gig_id'],
      'user_id': entry['user_id'],
      'section': entry['section'],
      field: iso,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'gig_id,user_id,section');
    _updateLocalMark(entry, field, iso);
  }

  Future<void> _applyMark(
    Map<String, dynamic> entry,
    String field,
    String? iso, {
    required String errorLabel,
  }) async {
    try {
      await _setMark(entry, field, iso);
    } catch (e) {
      debugPrint('$errorLabel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorLabel: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<String?> _pickDate(String helpText) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: helpText,
    );
    if (picked == null || !mounted) return null;
    return DateTime(picked.year, picked.month, picked.day).toIso8601String();
  }

  Future<void> _markInvoiced(Map<String, dynamic> entry) async {
    final iso = await _pickDate('Velg fakturadato');
    if (iso == null) return;
    await _applyMark(entry, 'crew_invoiced_at', iso,
        errorLabel: 'Feil ved markering som fakturert');
  }

  Future<void> _clearInvoiced(Map<String, dynamic> entry) async {
    await _applyMark(entry, 'crew_invoiced_at', null,
        errorLabel: 'Feil ved fjerning av fakturert');
  }

  Future<void> _markPaid(Map<String, dynamic> entry) async {
    final iso = await _pickDate('Velg betalingsdato');
    if (iso == null) return;
    await _applyMark(entry, 'crew_paid_at', iso,
        errorLabel: 'Feil ved markering som betalt');
  }

  Future<void> _clearPaid(Map<String, dynamic> entry) async {
    await _applyMark(entry, 'crew_paid_at', null,
        errorLabel: 'Feil ved fjerning av betalt');
  }

  /// Updates the one lineup-less entry in place.
  void _updateLocalMark(
      Map<String, dynamic> entry, String field, String? value) {
    final key = _markKey(entry);
    setState(() {
      for (final e in _entries) {
        if ((e['lineup_ids'] as List).isEmpty && _markKey(e) == key) {
          e[field] = value;
        }
      }
    });
  }

  void _updateLocalEntries(List<String> lineupIds, String field, String? value) {
    final idSet = lineupIds.toSet();
    setState(() {
      for (final entry in _entries) {
        final entryLineupIds = List<String>.from(entry['lineup_ids'] as List);
        if (entryLineupIds.any((id) => idSet.contains(id))) {
          entry[field] = value;
        }
      }
    });
  }

  String _formatAmount(double amount) {
    final formatted = NumberFormat('#,##0', 'nb_NO').format(amount.round());
    return '$formatted kr';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      return _df.format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalOutstanding = _entries
        .where((e) => e['crew_paid_at'] == null)
        .fold(0.0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0));
    final totalAll = _entries
        .fold(0.0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0));

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gigghyrer',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),

          // Bank balance bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _bankConnected && _bankBalance != null
                  ? (_bankBalance! >= 0
                      ? Colors.green.shade900.withOpacity(0.15)
                      : Colors.red.shade900.withOpacity(0.15))
                  : cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _bankConnected && _bankBalance != null
                    ? (_bankBalance! >= 0 ? Colors.green.shade700 : Colors.red.shade700)
                    : cs.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_rounded, size: 20),
                const SizedBox(width: 10),
                if (_bankLoading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_bankConnected && _bankBalance != null) ...[
                  Text(
                    'DNB Saldo: ${_formatAmount(_bankBalance!)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _bankBalance! >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                    ),
                  ),
                  if (_bankUpdatedAt != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Oppdatert ${DateFormat('dd.MM HH:mm').format(_bankUpdatedAt!.toLocal())}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadBankBalance,
                    tooltip: 'Oppdater saldo',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ] else ...[
                  Text(
                    'DNB bedriftskonto',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _connectBank,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Koble til DNB', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Summary bar
          if (_entries.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Utestående: ${_formatAmount(totalOutstanding)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    'Totalt: ${_formatAmount(totalAll)}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text('Ingen gigghyrer',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Temporary: what the loader actually found, so a
                          // wrong total can be diagnosed from the page itself.
                          if (_diag.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  dense: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  leading: Icon(Icons.bug_report_outlined,
                                      size: 18, color: cs.onSurfaceVariant),
                                  title: Text('Diagnose',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurfaceVariant)),
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 12),
                                      child: SelectableText(
                                        _diag.join('\n'),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Expanded(child: _buildGroupedList(_entries, cs)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<Map<String, dynamic>> entries, ColorScheme cs) {
    // Group by gig_id
    final grouped = <String, List<Map<String, dynamic>>>{};
    final gigOrder = <String>[];
    for (final e in entries) {
      final gigId = e['gig_id'] as String;
      if (!grouped.containsKey(gigId)) {
        grouped[gigId] = [];
        gigOrder.add(gigId);
      }
      grouped[gigId]!.add(e);
    }

    return ListView.builder(
      itemCount: gigOrder.length,
      itemBuilder: (context, gi) {
        final gigId = gigOrder[gi];
        final members = grouped[gigId]!;
        final first = members.first;
        final date = _formatDate(first['date_from'] as String?);
        final venue = first['venue_name'] as String? ?? '';
        final firma = first['customer_firma'] as String? ?? '';
        var offerTotal = (first['offer_total'] as num?)?.toDouble() ?? 0;

        // Fallback: estimate from lineup fees + markup if final_calc wasn't saved
        if (offerTotal == 0) {
          final offer = first['offer'] as Map<String, dynamic>?;
          if (offer != null) {
            final gigHire = members.fold<double>(
                0, (s, e) => s + ((e['hire_fee'] as num?)?.toDouble() ?? 0));
            final markupPct = (offer['markup_pct'] as num?)?.toDouble() ?? 0;
            final markupOnAll = offer['markup_on_all'] == true;
            final inear = offer['inear_included'] == true
                ? ((offer['inear_price'] as num?)?.toDouble() ?? 0) : 0.0;
            final transport = (offer['transport_price'] as num?)?.toDouble() ?? 0;
            final rehPerf = (offer['rehearsal_performers'] as num?)?.toInt() ?? 0;
            final rehCount = (offer['rehearsal_count'] as num?)?.toInt() ?? 0;
            final rehPrice = (offer['rehearsal_price_per_person'] as num?)?.toDouble() ?? 0;
            final rehTransport = (offer['rehearsal_transport'] as num?)?.toDouble() ?? 0;
            final rehearsalTotal = (rehPerf * rehCount * rehPrice) + rehTransport;
            final subtotal = gigHire + inear + transport + rehearsalTotal;
            final markupBase = markupOnAll ? subtotal : gigHire;
            offerTotal = subtotal + (markupBase * markupPct);
          }
        }

        // Totals for this gig
        final hireTotal = members.fold<double>(
            0, (sum, e) => sum + ((e['hire_fee'] as num?)?.toDouble() ?? 0));
        final expenseTotal = members.fold<double>(
            0, (sum, e) => sum + ((e['expense_total'] as num?)?.toDouble() ?? 0));
        final companyCardTotal = (first['company_card_total'] as num?)?.toDouble() ?? 0;
        final gigTotal = hireTotal + expenseTotal + companyCardTotal;
        final profit = offerTotal - gigTotal;
        final unpaidTotal = members
            .where((e) => e['crew_paid_at'] == null)
            .fold<double>(0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0));

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gig header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    Text(date,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(venue,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          if (firma.isNotEmpty)
                            Text(firma,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (offerTotal > 0)
                      Text('Tilbud: ${_formatAmount(offerTotal)}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    if (offerTotal > 0 && first['offer'] != null && (first['offer'] as Map)['final_calc'] == null)
                      Tooltip(
                        message: 'Estimert — åpne og lagre tilbudet for nøyaktig total',
                        child: Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                      ),
                  ],
                ),
              ),
              // Member rows
              ...members.map((e) {
                final name = e['name'] as String? ?? '';
                final section = e['section'] as String? ?? '';
                final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                final numShows = e['num_shows'] as int? ?? 1;
                final isRehearsal = e['is_rehearsal'] == true;
                final invoicedAt = e['crew_invoiced_at'] as String?;
                final paidAt = e['crew_paid_at'] as String?;
                final memberExpense = (e['expense_total'] as num?)?.toDouble() ?? 0;
                final extraTotal = (e['extra_total'] as num?)?.toDouble() ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(section,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                      SizedBox(
                        width: 50,
                        // A rehearsal is not shows, and the booking/ekstra
                        // rows are not either — "0 show" was noise on both.
                        child: Text(
                            isRehearsal
                                ? 'Prøve'
                                : (numShows > 0 ? '$numShows show' : ''),
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center),
                      ),
                      SizedBox(
                        width: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatAmount(amount),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (extraTotal > 0)
                              Text('ekstra: ${_formatAmount(extraTotal)}',
                                  style: TextStyle(
                                      fontSize: 10, color: cs.onSurfaceVariant)),
                            if (memberExpense > 0)
                              Text('utlegg: ${_formatAmount(memberExpense)}',
                                  style: TextStyle(
                                      fontSize: 10, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: invoicedAt != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle,
                                      size: 13, color: Colors.green),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                        'Fakt. ${_formatDate(invoicedAt)}',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.green),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  InkWell(
                                    onTap: () => _clearInvoiced(e),
                                    child: Icon(Icons.close,
                                        size: 13, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              )
                            : FilledButton.icon(
                                onPressed: () => _markInvoiced(e),
                                icon: const Icon(Icons.receipt, size: 12),
                                label: const Text('Fakturert',
                                    style: TextStyle(fontSize: 10)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 110,
                        child: paidAt != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                        'Betalt ${_formatDate(paidAt)}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: cs.onSurfaceVariant),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  InkWell(
                                    onTap: () => _clearPaid(e),
                                    child: Icon(Icons.close,
                                        size: 13, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              )
                            : FilledButton.icon(
                                onPressed: () => _markPaid(e),
                                icon: const Icon(Icons.check, size: 14),
                                label: const Text('Betalt',
                                    style: TextStyle(fontSize: 10)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              }),
              // Gig footer — full economy breakdown
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Column(
                  children: [
                    _footerRow('Honorarer', hireTotal, cs),
                    if (expenseTotal > 0)
                      _footerRow('Utlegg', expenseTotal, cs),
                    if (companyCardTotal > 0)
                      _footerRow('Firmakort', companyCardTotal, cs),
                    _footerRow('Totalt', gigTotal, cs, bold: true),
                    if (offerTotal > 0) ...[
                      const Divider(height: 8),
                      _footerRow('Tilbudspris', offerTotal, cs),
                      _footerRow('Vi sitter igjen med', profit, cs,
                          bold: true,
                          color: profit >= 0 ? Colors.green : Colors.red),
                    ],
                    // Remaining to pay
                    if (unpaidTotal > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Gjenstår å betale: ${_formatAmount(unpaidTotal)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _footerRow(String label, double amount, ColorScheme cs,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: color ?? cs.onSurface,
              )),
          Text(_formatAmount(amount.abs()),
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: color ?? cs.onSurface,
              )),
        ],
      ),
    );
  }
}
