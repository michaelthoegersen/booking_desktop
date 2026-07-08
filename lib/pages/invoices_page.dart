import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../localization/s.dart';
import '../models/invoice.dart';
import '../services/invoice_service.dart';
import '../services/invoice_pdf_service.dart';
import '../platform/pdf_saver.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  List<Invoice> _invoices = [];
  bool _loading = true;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await InvoiceService.listInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${S.t('loadError')}: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Invoice> get _filtered {
    if (_statusFilter == 'all') return _invoices;
    return _invoices.where((i) => i.status == _statusFilter).toList();
  }

  Future<void> _downloadPdf(Invoice invoice) async {
    try {
      final bytes = await InvoicePdfService.generatePdf(invoice);
      final safe = invoice.production
          .replaceAll(RegExp(r'[\/\\\:\*\?\"\<\>\|]'), '_');
      await savePdf(bytes, "Faktura ${invoice.invoiceNumber} $safe.pdf");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${S.t('pdfError')}: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markPaid(Invoice invoice) async {
    try {
      await InvoiceService.updateStatus(invoice.id!, 'paid');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${S.t('error')}: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Invoice invoice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(S.t('deleteInvoice')),
        content: Text(
          "Delete invoice ${invoice.invoiceNumber} for ${invoice.company}?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(S.t('delete')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await InvoiceService.deleteInvoice(invoice.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${S.t('error')}: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _showOptions(Invoice invoice) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(S.t('downloadPdf')),
              onTap: () {
                Navigator.pop(sheetCtx);
                _downloadPdf(invoice);
              },
            ),
            if (invoice.status == 'unpaid')
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(S.t('markAsPaid')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _markPaid(invoice);
                },
              ),
            if (invoice.status != 'cancelled')
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: Text(S.t('markAsCancelled')),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await InvoiceService.updateStatus(invoice.id!, 'cancelled');
                  await _load();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                S.t('delete'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _delete(invoice);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- HEADER ----
            Row(
              children: [
                Text(
                  S.t('invoices'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _statusFilter,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(S.t('all'))),
                    DropdownMenuItem(value: 'unpaid', child: Text(S.t('unpaid'))),
                    DropdownMenuItem(value: 'paid', child: Text(S.t('paid'))),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text(S.t('cancelled')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _statusFilter = v);
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                  tooltip: "Refresh",
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ---- TABLE HEADER ----
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _headerCell(S.t('invoiceNr'), flex: 2),
                  _headerCell(S.t('companies'), flex: 3),
                  _headerCell(S.t('production'), flex: 3),
                  _headerCell(S.t('date'), flex: 2),
                  _headerCell(S.t('totalInclVat'), flex: 2),
                  _headerCell(S.t('status'), flex: 2),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ---- LIST ----
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            S.t('noInvoicesFound'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final inv = _filtered[i];
                            return _InvoiceRow(
                              invoice: inv,
                              onTap: () => _showOptions(inv),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ============================================================
// INVOICE ROW
// ============================================================

class _InvoiceRow extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;

  const _InvoiceRow({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color statusColor;
    switch (invoice.status) {
      case 'paid':
        statusColor = Colors.green;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.orange;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            _cell(invoice.invoiceNumber, flex: 2, bold: true),
            _cell(invoice.company, flex: 3),
            _cell(invoice.production, flex: 3),
            _cell(
              DateFormat("dd.MM.yyyy").format(invoice.invoiceDate),
              flex: 2,
            ),
            _cell(_formatNok(invoice.totalInclVat), flex: 2),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    invoice.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String value, {int flex = 1, bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        style: TextStyle(
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _formatNok(double v) =>
      "kr ${NumberFormat('#,###').format(v)}";
}
