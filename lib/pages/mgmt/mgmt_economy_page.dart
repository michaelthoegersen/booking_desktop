import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/tripletex_service.dart';
import '../../state/active_company.dart';
class MgmtEconomyPage extends StatefulWidget {
  const MgmtEconomyPage({super.key});

  @override
  State<MgmtEconomyPage> createState() => _MgmtEconomyPageState();
}

class _MgmtEconomyPageState extends State<MgmtEconomyPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabCtrl;
  final _nf = NumberFormat('#,##0.00', 'nb_NO');

  String? get _companyId => activeCompanyNotifier.value?.id;

  bool _checkingTokens = true;
  bool _hasTokens = false;

  // Tab 1: Outgoing invoices
  bool _invoicesLoading = true;
  List<Map<String, dynamic>> _invoices = [];
  String _invoiceFilter = 'all';

  // Tab 2: Supplier invoices needing bokføring (no postings on voucher)
  bool _unbookedLoading = true;
  List<Map<String, dynamic>> _unbookedInvoices = [];

  // Tab 3: Supplier invoices already bokført
  bool _bookedLoading = true;
  List<Map<String, dynamic>> _bookedInvoices = [];

  // Cached reference data for bokfør dialog
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _vatTypes = [];
  bool _refDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _checkTokens();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    super.dispose();
  }

  void _onCompanyChanged() {
    _refDataLoaded = false;
    _checkTokens();
  }

  Future<void> _checkTokens() async {
    if (_companyId == null) return;
    setState(() => _checkingTokens = true);
    try {
      final company = await _sb
          .from('companies')
          .select('tripletex_consumer_token, tripletex_employee_token')
          .eq('id', _companyId!)
          .maybeSingle();
      final consumer = company?['tripletex_consumer_token'] as String?;
      final employee = company?['tripletex_employee_token'] as String?;
      _hasTokens = consumer != null &&
          consumer.isNotEmpty &&
          employee != null &&
          employee.isNotEmpty;
    } catch (e) {
      debugPrint('Check tokens error: $e');
      _hasTokens = false;
    }
    if (mounted) {
      setState(() => _checkingTokens = false);
      if (_hasTokens) _loadAll();
    }
  }

  Future<void> _loadAll() async {
    _loadInvoices();
    _loadSupplierInvoices();
    if (!_refDataLoaded) _loadReferenceData();
  }

  // ── Load: reference data (accounts + VAT types) ─────────────────────

  Future<void> _loadReferenceData() async {
    if (_companyId == null) return;
    try {
      final results = await Future.wait([
        TripletexService.listAccounts(_companyId!),
        TripletexService.listVatTypes(_companyId!),
      ]);
      _accounts = results[0];
      _vatTypes = results[1];
      _refDataLoaded = true;
    } catch (e) {
      debugPrint('Load reference data error: $e');
    }
  }

  // ── Load: outgoing invoices ───────────────────────────────────────────

  Future<void> _loadInvoices() async {
    if (_companyId == null) return;
    setState(() => _invoicesLoading = true);
    try {
      final filter = _invoiceFilter == 'all' ? null : _invoiceFilter;
      final res = await TripletexService.listInvoices(
        _companyId!,
        invoiceStatus: filter,
      );
      if (mounted) setState(() => _invoices = res);
    } catch (e) {
      debugPrint('Load invoices error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved lasting av fakturaer: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _invoicesLoading = false);
  }

  // ── Load: bilagsmottak + supplier invoices ────────────────────────────

  Future<void> _loadSupplierInvoices() async {
    if (_companyId == null) return;
    setState(() {
      _unbookedLoading = true;
      _bookedLoading = true;
    });
    try {
      // Fetch bilagsmottak AND supplier invoices in parallel
      final results = await Future.wait([
        TripletexService.listVoucherReception(_companyId!),
        TripletexService.listSupplierInvoices(_companyId!),
      ]);

      final receptionVouchers = results[0];
      final supplierInvs = results[1];

      // Map supplier invoices by voucherId for quick lookup
      final invByVoucherId = <int, Map<String, dynamic>>{};
      for (final inv in supplierInvs) {
        final v = inv['voucher'] as Map<String, dynamic>?;
        final vid = (v?['id'] as num?)?.toInt();
        if (vid != null) invByVoucherId[vid] = inv;
      }

      final unbooked = <Map<String, dynamic>>[];
      final receptionVoucherIds = <int>{};

      for (final voucher in receptionVouchers) {
        final vid = (voucher['id'] as num).toInt();
        receptionVoucherIds.add(vid);
        final linked = invByVoucherId[vid];

        if (linked != null) {
          // Already a supplier invoice — use its rich data
          unbooked.add(linked);
        } else {
          // Extract what we can from postings
          final postings = voucher['postings'] as List<dynamic>? ?? [];
          final desc = (voucher['description'] as String? ?? '').trim();
          final hasEdi = voucher['ediDocument'] != null;
          final isInvoice = desc.toLowerCase().startsWith('faktura');

          String? supplierName;
          int? supplierId;
          double amount = 0;

          for (final p in postings) {
            if (p is! Map<String, dynamic>) continue;
            final s = p['supplier'] as Map<String, dynamic>?;
            if (s != null && s['name'] != null) {
              supplierName = s['name'] as String;
              supplierId = (s['id'] as num?)?.toInt();
            }
            final a = (p['amountGross'] as num?)?.toDouble() ?? 0;
            if (a.abs() > amount.abs()) amount = a;
          }

          // Only show real invoices
          if (supplierName == null && !hasEdi && !isInvoice) continue;

          unbooked.add({
            '_isReceptionOnly': true,
            '_voucher': voucher,
            'id': vid,
            'voucher': voucher,
            'supplier': supplierName != null
                ? {'id': supplierId, 'name': supplierName}
                : null,
            '_supplierName': supplierName ?? '',
            'amount': amount,
            'invoiceDate': voucher['date'] ?? '',
            'invoiceDueDate': '',
            'invoiceNumber': voucher['vendorInvoiceNumber'] ?? '',
            '_description': desc,
          });
        }
      }

      // Also add supplier invoices NOT in bilagsmottak that need bokføring
      for (final inv in supplierInvs) {
        final v = inv['voucher'] as Map<String, dynamic>?;
        final vid = (v?['id'] as num?)?.toInt();
        if (vid != null && receptionVoucherIds.contains(vid)) continue;
        final postings = v?['postings'] as List<dynamic>?;
        if (postings != null && postings.isNotEmpty) continue;
        unbooked.add(inv);
      }

      // Bokført = supplier invoices with voucher postings
      final booked = supplierInvs.where((inv) {
        final v = inv['voucher'] as Map<String, dynamic>?;
        final postings = v?['postings'] as List<dynamic>?;
        return postings != null && postings.isNotEmpty;
      }).toList();

      if (mounted) {
        setState(() {
          _unbookedInvoices = unbooked;
          _bookedInvoices = booked;
        });
      }
    } catch (e) {
      debugPrint('Load supplier invoices error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) {
      setState(() {
        _unbookedLoading = false;
        _bookedLoading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_checkingTokens) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasTokens) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Økonomi', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(Icons.account_balance_rounded,
                      size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    'Tripletex er ikke konfigurert',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Legg inn Consumer Token og Employee Token under Innstillinger for å koble til Tripletex.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.go('/m/settings'),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Gå til Innstillinger'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Økonomi', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: Colors.black,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: Colors.black,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: [
              const Tab(text: 'Utgående fakturaer'),
              Tab(text: 'Å bokføre (${_unbookedInvoices.length})'),
              const Tab(text: 'Bokført'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildInvoicesTab(),
                _buildUnbookedTab(),
                _buildBookedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Tab 1: Outgoing invoices
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildInvoicesTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            _FilterChip(
              label: 'Alle',
              selected: _invoiceFilter == 'all',
              onTap: () {
                _invoiceFilter = 'all';
                _loadInvoices();
              },
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Ubetalt',
              selected: _invoiceFilter == 'isNotPaid',
              onTap: () {
                _invoiceFilter = 'isNotPaid';
                _loadInvoices();
              },
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Betalt',
              selected: _invoiceFilter == 'isPaid',
              onTap: () {
                _invoiceFilter = 'isPaid';
                _loadInvoices();
              },
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Oppdater',
              onPressed: _loadInvoices,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _invoicesLoading
              ? const Center(child: CircularProgressIndicator())
              : _invoices.isEmpty
                  ? Center(
                      child: Text('Ingen fakturaer funnet',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : _buildInvoiceTable(),
        ),
      ],
    );
  }

  Widget _buildInvoiceTable() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(cs.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Nr', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Kunde', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Beløp', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Dato', style: TextStyle(fontWeight: FontWeight.w900))),
          ],
          rows: _invoices.map((inv) {
            final nr = inv['invoiceNumber'] ?? inv['id'] ?? '';
            final customer = inv['customer'] as Map<String, dynamic>?;
            final customerName = customer?['name'] ?? '';
            final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
            final outstanding = (inv['amountOutstanding'] as num?)?.toDouble() ?? 0;
            final isPaid = outstanding == 0 && amount > 0;
            final date = inv['invoiceDate'] ?? '';

            return DataRow(cells: [
              DataCell(Text('$nr')),
              DataCell(Text('$customerName')),
              DataCell(Text(_nf.format(amount))),
              DataCell(_statusBadge(isPaid ? 'Betalt' : 'Ubetalt', isPaid)),
              DataCell(Text('$date')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Tab 2: Supplier invoices needing bokføring
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildUnbookedTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Oppdater',
              onPressed: _loadSupplierInvoices,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _unbookedLoading
              ? const Center(child: CircularProgressIndicator())
              : _unbookedInvoices.isEmpty
                  ? Center(
                      child: Text('Ingen fakturaer å bokføre',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : _buildUnbookedTable(),
        ),
      ],
    );
  }

  Widget _buildUnbookedTable() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(cs.surfaceContainerLow),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Beskrivelse', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Leverandør', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Beløp', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Forfallsdato', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Fakturanr', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.w900))),
          ],
          rows: _unbookedInvoices.map((inv) {
            final isReceptionOnly = inv['_isReceptionOnly'] == true;
            final supplier = inv['supplier'];
            final supplierName = inv['_supplierName'] as String? ??
                (supplier is Map<String, dynamic> ? (supplier['name'] as String? ?? '') : '');
            final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
            final dueDate = inv['invoiceDueDate'] ?? '';
            final invoiceNumber = inv['invoiceNumber'] ?? '';
            final description = isReceptionOnly ? (inv['_description'] as String? ?? '') : '';

            return DataRow(cells: [
              DataCell(SizedBox(
                width: 220,
                child: Text(
                  description.isNotEmpty ? description : (supplierName.isNotEmpty ? supplierName : '—'),
                  overflow: TextOverflow.ellipsis,
                ),
              )),
              DataCell(SizedBox(
                width: 150,
                child: Text(supplierName, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(amount != 0 ? _nf.format(amount.abs()) : '')),
              DataCell(Text('$dueDate')),
              DataCell(Text('$invoiceNumber')),
              DataCell(
                FilledButton.icon(
                  onPressed: () => _showBokforDialog(inv),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Bokfør'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Bokfør dialog ───────────────────────────────────────────────────

  Future<void> _showBokforDialog(Map<String, dynamic> inv) async {
    if (_companyId == null) return;

    final isReceptionOnly = inv['_isReceptionOnly'] == true;
    final voucher = inv['voucher'] as Map<String, dynamic>?;
    final voucherId = (voucher?['id'] as num?)?.toInt() ?? (inv['id'] as num?)?.toInt();

    if (voucherId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fakturaen mangler voucher'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // For reception-only items, auto-open the PDF attachment
    if (isReceptionOnly) {
      final attachment = voucher?['attachment'] as Map<String, dynamic>?;
      final attachmentId = (attachment?['id'] as num?)?.toInt();
      if (attachmentId != null) {
        TripletexService.downloadAndOpenDocument(_companyId!, attachmentId)
            .then((_) {})
            .catchError((e) { debugPrint('Open attachment error: $e'); });
      }
    }

    // For already-registered supplier invoices, we have the ID
    int? supplierInvoiceId;
    if (!isReceptionOnly) {
      supplierInvoiceId = (inv['id'] as num).toInt();
    }

    final supplierName = inv['_supplierName'] as String? ??
        (inv['supplier'] is Map<String, dynamic>
            ? (inv['supplier']['name'] as String? ?? '')
            : '');
    final invoiceAmount = ((inv['amount'] as num?)?.toDouble() ?? 0).abs();
    final invoiceDate = inv['invoiceDate'] as String? ?? '';
    final dueDate = inv['invoiceDueDate'] as String? ?? '';

    // Filter to common expense accounts (4000-7999 range typically)
    final expenseAccounts = _accounts.where((a) {
      final nr = (a['number'] as num?)?.toInt() ?? 0;
      return nr >= 4000 && nr <= 7999;
    }).toList();

    // State for dialog
    Map<String, dynamic>? selectedAccount;
    bool isBusy = false;
    String? errorMsg;

    // Find VAT type 0 (Ingen avgiftsbehandling) — ikke mva-pliktig
    final zeroVat = _vatTypes.where((v) {
      final raw = v['number'];
      final nr = raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1;
      return nr == 0;
    }).firstOrNull;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('Bokfør bilag'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (supplierName.isNotEmpty)
                          _infoRow('Leverandør', supplierName),
                        if (invoiceAmount > 0)
                          _infoRow('Beløp inkl. mva', _nf.format(invoiceAmount)),
                        if (invoiceDate.isNotEmpty)
                          _infoRow('Fakturadato', invoiceDate),
                        if (dueDate.isNotEmpty)
                          _infoRow('Forfallsdato', dueDate),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Account picker with search
                  const Text('Kostnadskonto',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (textEditingValue) {
                      final q = textEditingValue.text.toLowerCase();
                      if (q.isEmpty) return expenseAccounts;
                      return expenseAccounts.where((a) {
                        final nr = '${a['number'] ?? ''}';
                        final name = (a['name'] as String? ?? '').toLowerCase();
                        return nr.contains(q) || name.contains(q);
                      });
                    },
                    displayStringForOption: (a) {
                      final nr = a['number'] ?? '';
                      final name = a['name'] ?? '';
                      return '$nr — $name';
                    },
                    onSelected: (val) => setDlgState(() => selectedAccount = val),
                    fieldViewBuilder: (ctx, textCtrl, focusNode, onSubmit) {
                      return TextField(
                        controller: textCtrl,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Søk kontonr eller navn...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: selectedAccount != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    textCtrl.clear();
                                    setDlgState(() => selectedAccount = null);
                                  },
                                )
                              : null,
                        ),
                        style: const TextStyle(fontSize: 13),
                      );
                    },
                    optionsViewBuilder: (ctx, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 250, maxWidth: 460),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (ctx, i) {
                                final a = options.elementAt(i);
                                final nr = a['number'] ?? '';
                                final name = a['name'] ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text('$nr — $name',
                                      style: const TextStyle(fontSize: 13)),
                                  onTap: () => onSelected(a),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // MVA info (hardkodet 0% — ikke mva-pliktig)
                  Row(
                    children: [
                      const Text('MVA-kode: ',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('0 — Ingen avgiftsbehandling (0%)',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),

                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Avbryt'),
              ),
              FilledButton.icon(
                onPressed: isBusy || selectedAccount == null
                    ? null
                    : () async {
                        setDlgState(() {
                          isBusy = true;
                          errorMsg = null;
                        });

                        try {
                          final accountId = (selectedAccount!['id'] as num).toInt();
                          final vatId = zeroVat != null
                              ? (zeroVat['id'] as num).toInt()
                              : null;

                          final desc = supplierName;
                          final vDate = invoiceDate.isNotEmpty
                              ? invoiceDate
                              : DateFormat('yyyy-MM-dd').format(DateTime.now());

                          // For reception-only items: register as supplier invoice first
                          var finalSupInvId = supplierInvoiceId;
                          if (finalSupInvId == null) {
                            final vendorId = inv['supplier'] is Map<String, dynamic>
                                ? (inv['supplier']['id'] as num?)?.toInt()
                                : null;

                            // Try to find existing supplier invoice for this voucher
                            try {
                              final existing = await TripletexService.findSupplierInvoiceByVoucher(
                                _companyId!, voucherId);
                              if (existing.isNotEmpty) {
                                finalSupInvId = (existing.first['id'] as num).toInt();
                              }
                            } catch (_) {}

                            // If not found, register as new supplier invoice
                            if (finalSupInvId == null) {
                              final regResult = await TripletexService.registerVoucherAsSupplierInvoice(
                                _companyId!,
                                voucherId: voucherId,
                                invoiceDate: vDate,
                                dueDate: dueDate.isNotEmpty ? dueDate : vDate,
                                invoiceNumber: (inv['invoiceNumber'] as String?)?.isNotEmpty == true
                                    ? inv['invoiceNumber'] as String
                                    : null,
                                supplierId: vendorId,
                              );
                              final regValue = regResult['value'] as Map<String, dynamic>?;
                              finalSupInvId = (regValue?['id'] as num?)?.toInt();
                              if (finalSupInvId == null) {
                                throw Exception('Kunne ikke registrere leverandørfaktura');
                              }
                            }
                          }

                          await TripletexService.bokforSupplierInvoice(
                            _companyId!,
                            supplierInvoiceId: finalSupInvId,
                            voucherId: voucherId,
                            accountId: accountId,
                            vatTypeId: vatId,
                            description: desc,
                            date: vDate,
                          );

                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setDlgState(() {
                            isBusy = false;
                            errorMsg = '$e';
                          });
                        }
                      },
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('Bokfør'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faktura bokført')),
      );
      _loadSupplierInvoices();
    }
  }

  Widget _infoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Tab 3: Bokførte leverandørfakturaer
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildBookedTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Oppdater',
              onPressed: _loadSupplierInvoices,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _bookedLoading
              ? const Center(child: CircularProgressIndicator())
              : _bookedInvoices.isEmpty
                  ? Center(
                      child: Text('Ingen bokførte leverandørfakturaer',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : _buildBookedTable(),
        ),
      ],
    );
  }

  Widget _buildBookedTable() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(cs.surfaceContainerLow),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Leverandør', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Beløp', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Fakturadato', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Forfallsdato', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w900))),
            DataColumn(label: Text('Handlinger', style: TextStyle(fontWeight: FontWeight.w900))),
          ],
          rows: _bookedInvoices.map((inv) {
            final supplier = inv['supplier'];
            final supplierName = supplier is Map<String, dynamic>
                ? (supplier['name'] as String? ?? '')
                : '';
            final amount = (inv['amount'] as num?)?.toDouble() ?? 0.0;
            final outstanding = (inv['outstandingAmount'] as num?)?.toDouble() ?? amount;
            final date = inv['invoiceDate'] ?? '';
            final dueDate = inv['invoiceDueDate'] ?? '';
            final invoiceId = (inv['id'] as num).toInt();
            final isPaid = outstanding == 0 && amount != 0;

            return DataRow(cells: [
              DataCell(SizedBox(
                width: 200,
                child: Text(supplierName, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(amount != 0 ? _nf.format(amount.abs()) : '')),
              DataCell(Text('$date')),
              DataCell(Text('$dueDate')),
              DataCell(_statusBadge(isPaid ? 'Betalt' : 'Ubetalt', isPaid)),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPaid) ...[
                    TextButton(
                      onPressed: () => _approveInvoice(invoiceId),
                      child: const Text('Godkjenn'),
                    ),
                    TextButton(
                      onPressed: () => _showPaymentDialog(
                        invoiceId,
                        amount.abs(),
                        dueDate: '$dueDate',
                      ),
                      child: const Text('Betal'),
                    ),
                  ],
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _approveInvoice(int invoiceId) async {
    if (_companyId == null) return;
    try {
      await TripletexService.approveSupplierInvoice(_companyId!, invoiceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faktura godkjent')),
        );
      }
      _loadSupplierInvoices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved godkjenning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showPaymentDialog(int invoiceId, double defaultAmount, {String? kidReference, String? dueDate}) async {
    if (_companyId == null) return;
    final amountCtrl = TextEditingController(text: defaultAmount.toStringAsFixed(2));
    final kidCtrl = TextEditingController(text: kidReference ?? '');

    // Default to due date or today
    DateTime selectedDate = DateTime.now();
    if (dueDate != null && dueDate.isNotEmpty) {
      selectedDate = DateTime.tryParse(dueDate) ?? DateTime.now();
    }

    bool isBusy = false;
    String? errorMsg;

    // Load payment types
    List<Map<String, dynamic>> paymentTypes = [];
    Map<String, dynamic>? selectedPaymentType;
    bool loadingTypes = true;

    // Show dialog immediately, load types async
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Load payment types on first build
        if (loadingTypes) {
          TripletexService.listPaymentTypes(_companyId!).then((types) {
            // Show all active payment types
            paymentTypes = types.where((t) {
              return t['isInactive'] != true;
            }).toList();
            if (paymentTypes.isNotEmpty) selectedPaymentType = paymentTypes.first;
            loadingTypes = false;
            if (ctx.mounted) (ctx as Element).markNeedsBuild();
          }).catchError((e) {
            debugPrint('Load payment types error: $e');
            loadingTypes = false;
            errorMsg = 'Kunne ikke laste betalingstyper: $e';
            if (ctx.mounted) (ctx as Element).markNeedsBuild();
          });
        }

        return StatefulBuilder(builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('Send til betaling'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Payment type dropdown
                  const Text('Betalingstype',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (loadingTypes)
                    const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (paymentTypes.isEmpty)
                    Text('Ingen betalingstyper funnet',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13))
                  else
                    DropdownButtonFormField<int>(
                      value: (selectedPaymentType?['id'] as num?)?.toInt(),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: paymentTypes.map((pt) {
                        final id = (pt['id'] as num).toInt();
                        final desc = pt['description'] as String? ?? 'Type $id';
                        return DropdownMenuItem(value: id, child: Text(desc, style: const TextStyle(fontSize: 13)));
                      }).toList(),
                      onChanged: (val) {
                        setDlgState(() {
                          selectedPaymentType = paymentTypes.firstWhere(
                            (pt) => (pt['id'] as num).toInt() == val,
                          );
                        });
                      },
                    ),

                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Beløp',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: kidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'KID / Referanse (valgfritt)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Betalingsdato: ',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setDlgState(() => selectedDate = picked);
                          }
                        },
                        child: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                      ),
                    ],
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Avbryt'),
              ),
              FilledButton.icon(
                onPressed: isBusy || selectedPaymentType == null
                    ? null
                    : () async {
                        setDlgState(() {
                          isBusy = true;
                          errorMsg = null;
                        });

                        final amount = double.tryParse(amountCtrl.text) ?? defaultAmount;
                        final payDate = DateFormat('yyyy-MM-dd').format(selectedDate);
                        final kid = kidCtrl.text.trim();
                        final payTypeId = (selectedPaymentType!['id'] as num).toInt();

                        try {
                          await TripletexService.addSupplierPayment(
                            _companyId!,
                            invoiceId: invoiceId,
                            paymentDate: payDate,
                            amount: amount,
                            paymentTypeId: payTypeId,
                            useDefaultPaymentType: false,
                            kidOrReceiverReference: kid.isNotEmpty ? kid : null,
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setDlgState(() {
                            isBusy = false;
                            errorMsg = '$e';
                          });
                        }
                      },
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Send til betaling'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed != true) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Betaling sendt til behandling')),
      );
    }
    _loadSupplierInvoices();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Widget _statusBadge(String label, bool isGreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGreen ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isGreen ? Colors.green.shade700 : Colors.orange.shade700,
        ),
      ),
    );
  }
}

// ── Filter chip widget ──────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.black : cs.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
