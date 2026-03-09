import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
// ──────────────────────────────────────────────────────────────────────────────
// MGMT GIG OFFERS LIST PAGE
// ──────────────────────────────────────────────────────────────────────────────

class MgmtGigOffersPage extends StatefulWidget {
  const MgmtGigOffersPage({super.key});

  @override
  State<MgmtGigOffersPage> createState() => _MgmtGigOffersPageState();
}

class _MgmtGigOffersPageState extends State<MgmtGigOffersPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('dd.MM.yyyy');

  bool _loading = true;
  List<Map<String, dynamic>> _offers = [];
  String _statusFilter = 'all';
  bool _showArchived = false;

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
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
      final rows = await _sb
          .from('gig_offers')
          .select('*, gigs!gig_offers_gig_id_fkey(venue_name, date_from, date_to)')
          .eq('company_id', _companyId!)
          .eq('archived', _showArchived)
          .order('created_at', ascending: false);
      _offers = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Load offers error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _offers;
    return _offers.where((o) => o['status'] == _statusFilter).toList();
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'inquiry':
        return 'Forespørsel';
      case 'confirmed':
        return 'Bekreftet';
      case 'invoiced':
        return 'Fakturert';
      case 'completed':
        return 'Fullført';
      case 'cancelled':
        return 'Avlyst';
      default:
        return s ?? '';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'inquiry':
        return Colors.orange;
      case 'confirmed':
        return Colors.green;
      case 'invoiced':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _deleteOffer(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett tilbud?'),
        content: const Text(
            'Er du sikker på at du vil slette dette tilbudet? Tilhørende gig blir også slettet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Slett', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      final offer = _offers.firstWhere((o) => o['id'] == id, orElse: () => {});
      final gigId = offer['gig_id'] as String?;
      // Delete offer first (has FK to gig with ON DELETE SET NULL)
      await _sb.from('gig_offers').delete().eq('id', id);
      // Then delete the gig
      if (gigId != null) {
        await _sb.from('gigs').delete().eq('id', gigId);
      }
      _load();
    }
  }

  Future<void> _setArchived(String offerId, bool archived) async {
    // Find the offer to get gig_id
    final offer = _offers.firstWhere((o) => o['id'] == offerId, orElse: () => {});
    await _sb.from('gig_offers').update({'archived': archived}).eq('id', offerId);
    final gigId = offer['gig_id'] as String?;
    if (gigId != null) {
      await _sb.from('gigs').update({'archived': archived}).eq('id', gigId);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(_showArchived ? 'Arkiv' : 'Tilbud',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(width: 12),
              IconButton(
                tooltip: _showArchived ? 'Vis aktive tilbud' : 'Vis arkiv',
                icon: Icon(
                  _showArchived ? Icons.inbox_rounded : Icons.archive_outlined,
                  color: _showArchived ? Colors.orange : cs.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() => _showArchived = !_showArchived);
                  _load();
                },
              ),
              const Spacer(),
              // Status filter
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle')),
                    DropdownMenuItem(value: 'inquiry', child: Text('Forespørsel')),
                    DropdownMenuItem(value: 'confirmed', child: Text('Bekreftet')),
                    DropdownMenuItem(value: 'invoiced', child: Text('Fakturert')),
                    DropdownMenuItem(value: 'completed', child: Text('Fullført')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Avlyst')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (!_showArchived)
                FilledButton.icon(
                  onPressed: () => context.go('/m/offers/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nytt tilbud'),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.request_quote_rounded,
                                size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                                _showArchived
                                    ? 'Ingen arkiverte tilbud'
                                    : 'Ingen tilbud ennå',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final o = _filtered[i];
                          final status = o['status'] as String? ?? 'inquiry';
                          final customer =
                              o['customer_firma'] as String? ?? '';
                          final name =
                              o['customer_name'] as String? ?? '';
                          final gig = o['gigs'] as Map<String, dynamic>?;
                          final venue = gig?['venue_name'] as String? ?? '';
                          final dateFrom = gig?['date_from'] as String?;
                          final dateTo = gig?['date_to'] as String?;
                          String gigDates = '';
                          if (dateFrom != null) {
                            gigDates = _df.format(DateTime.parse(dateFrom));
                            if (dateTo != null && dateTo != dateFrom) {
                              gigDates += ' – ${_df.format(DateTime.parse(dateTo))}';
                            }
                          }
                          final created = o['created_at'] != null
                              ? _df.format(
                                  DateTime.parse(o['created_at'] as String))
                              : '';

                          return GestureDetector(
                            onTap: () =>
                                context.go('/m/offers/${o['id']}'),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: cs.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  // Date
                                  SizedBox(
                                    width: 90,
                                    child: Text(created,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: cs.onSurfaceVariant)),
                                  ),
                                  // Customer
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer.isNotEmpty
                                              ? customer
                                              : (name.isNotEmpty
                                                  ? name
                                                  : 'Uten kunde'),
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w900),
                                        ),
                                        if (customer.isNotEmpty &&
                                            name.isNotEmpty)
                                          Text(name,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant)),
                                        if (venue.isNotEmpty)
                                          Text(venue,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant)),
                                        if (gigDates.isNotEmpty)
                                          Text(gigDates,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  // Status badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status)
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border: Border.all(
                                          color: _statusColor(status)
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _statusLabel(status),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _statusColor(status),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Archive / Restore
                                  IconButton(
                                    tooltip: _showArchived
                                        ? 'Gjenopprett'
                                        : 'Arkiver',
                                    icon: Icon(
                                      _showArchived
                                          ? Icons.unarchive_outlined
                                          : Icons.archive_outlined,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onPressed: () => _setArchived(
                                      o['id'] as String,
                                      !_showArchived,
                                    ),
                                  ),
                                  // Delete
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 18,
                                        color: cs.onSurfaceVariant),
                                    onPressed: () =>
                                        _deleteOffer(o['id'] as String),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
