import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/email_service.dart';
import '../../services/reiseregning_pdf_helper.dart';
import '../../state/active_company.dart';

// ──────────────────────────────────────────────────────────────────────────────
// MGMT EXPENSES PAGE — Admin approve/reject expenses
// ──────────────────────────────────────────────────────────────────────────────

class MgmtExpensesPage extends StatefulWidget {
  const MgmtExpensesPage({super.key});

  @override
  State<MgmtExpensesPage> createState() => _MgmtExpensesPageState();
}

class _MgmtExpensesPageState extends State<MgmtExpensesPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('dd.MM.yyyy');

  bool _loading = true;
  List<Map<String, dynamic>> _expenses = [];
  String _statusFilter = 'pending';

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
        setState(() {
          _expenses = [];
          _loading = false;
        });
        return;
      }

      final rows = await _sb
          .from('expenses')
          .select('*, profiles!expenses_user_id_profiles_fkey(name)')
          .eq('company_id', _companyId!)
          .order('created_at', ascending: false);

      _expenses = List<Map<String, dynamic>>.from(rows);
    } catch (e, st) {
      debugPrint('Load expenses error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feil ved lasting av utlegg: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    return _expenses
        .where((e) => (e['status'] as String?) == _statusFilter)
        .toList();
  }

  Future<void> _approve(Map<String, dynamic> expense) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      await _sb.from('expenses').update({
        'status': 'approved',
        'approved_by': uid,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', expense['id'] as String);

      // If no gig linked → reiseregning flow: generate PDF and send to ebilag
      if (expense['gig_id'] == null) {
        await _sendReiseregning(expense);
      }

      // Notify the submitter
      await _notifySubmitter(expense, 'approved');

      await _load();
    } catch (e) {
      debugPrint('Approve expense error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved godkjenning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> expense) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avvis utlegg'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            hintText: 'Grunn for avvisning',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            child: const Text('Avvis'),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      final uid = _sb.auth.currentUser?.id;
      await _sb.from('expenses').update({
        'status': 'rejected',
        'approved_by': uid,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'rejection_reason': reason.isNotEmpty ? reason : null,
      }).eq('id', expense['id'] as String);

      // Notify the submitter
      await _notifySubmitter(expense, 'rejected');

      await _load();
    } catch (e) {
      debugPrint('Reject expense error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved avvisning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Notify the expense submitter that their expense was approved/rejected.
  Future<void> _notifySubmitter(Map<String, dynamic> expense, String status) async {
    try {
      final userId = expense['user_id'] as String?;
      if (userId == null) return;

      final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
      final amountStr = '${NumberFormat('#,##0', 'nb_NO').format(amount.round())} kr';

      final title = status == 'approved'
          ? 'Utlegg godkjent'
          : 'Utlegg avvist';
      final body = status == 'approved'
          ? 'Utlegget ditt på $amountStr er godkjent'
          : 'Utlegget ditt på $amountStr er avvist';

      await _sb.functions.invoke('notify-company', body: {
        'company_id': _companyId,
        'type': 'expense',
        'title': title,
        'body': body,
        'user_ids': [userId],
      });
    } catch (e) {
      debugPrint('Notify submitter error (non-critical): $e');
    }
  }

  /// Generate and send reiseregning PDF to ebilag.
  Future<void> _sendReiseregning(Map<String, dynamic> expense) async {
    try {
      // Import reiseregning service dynamically
      final expenseId = expense['id'] as String;
      final amount = (expense['amount'] as num).toDouble();
      final vendor = expense['vendor'] as String? ?? '';
      final receiptDate = expense['receipt_date'] as String?;
      final description = expense['description'] as String? ?? '';
      final profile = expense['profiles'] as Map<String, dynamic>?;
      final employeeName = profile?['name'] as String? ?? 'Ukjent';

      // Get signed URL for receipt image
      String? receiptImageUrl;
      final receiptPath = expense['receipt_url'] as String?;
      if (receiptPath != null && receiptPath.isNotEmpty) {
        receiptImageUrl = await _sb.storage
            .from('expense-receipts')
            .createSignedUrl(receiptPath, 300);
      }

      // Generate PDF using the pdf package
      final pdfBytes = await _generateReiseregningPdf(
        employeeName: employeeName,
        amount: amount,
        vendor: vendor,
        receiptDate: receiptDate,
        description: description,
        receiptImageUrl: receiptImageUrl,
      );

      // Send email with PDF attachment
      await EmailService.sendEmailWithAttachment(
        to: 'complete@ebilag.com',
        subject: 'Reiseregning — $employeeName — ${_df.format(DateTime.now())}',
        body: 'Vedlagt reiseregning for $employeeName.\n\n'
            'Beløp: ${NumberFormat('#,##0.00', 'nb_NO').format(amount)} kr\n'
            'Leverandør: $vendor\n'
            'Dato: ${receiptDate ?? "Ikke oppgitt"}\n'
            'Beskrivelse: $description',
        attachmentBytes: pdfBytes,
        attachmentFilename: 'reiseregning_${employeeName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      // Mark reiseregning as sent
      await _sb.from('expenses').update({
        'reiseregning_sent_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', expenseId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reiseregning sendt til ebilag'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Send reiseregning error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke sende reiseregning: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Generate a simple reiseregning PDF.
  Future<Uint8List> _generateReiseregningPdf({
    required String employeeName,
    required double amount,
    required String vendor,
    required String? receiptDate,
    required String description,
    String? receiptImageUrl,
  }) async {
    return ReiseregningPdfHelper.generatePdf(
      employeeName: employeeName,
      amount: amount,
      vendor: vendor,
      receiptDate: receiptDate,
      description: description,
      receiptImageUrl: receiptImageUrl,
    );
  }

  String _formatAmount(double amount) {
    return '${NumberFormat('#,##0', 'nb_NO').format(amount.round())} kr';
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
    final filtered = _filtered;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('Utlegg', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Ventende')),
                    DropdownMenuItem(value: 'approved', child: Text('Godkjent')),
                    DropdownMenuItem(value: 'rejected', child: Text('Avvist')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pending count badge
          if (_statusFilter == 'pending')
            Builder(
              builder: (_) {
                final pendingCount = _expenses
                    .where((e) => e['status'] == 'pending')
                    .length;
                final pendingTotal = _expenses
                    .where((e) => e['status'] == 'pending')
                    .fold<double>(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions, size: 20, color: Colors.orange),
                      const SizedBox(width: 10),
                      Text(
                        '$pendingCount ventende utlegg — totalt ${_formatAmount(pendingTotal)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              'Ingen ${_statusFilter == 'pending' ? 'ventende' : _statusFilter == 'approved' ? 'godkjente' : 'avviste'} utlegg',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          return _buildExpenseRow(e, cs);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseRow(Map<String, dynamic> e, ColorScheme cs) {
    final profile = e['profiles'] as Map<String, dynamic>?;
    final name = profile?['name'] as String? ?? 'Ukjent';
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    final vendor = e['vendor'] as String? ?? '';
    final description = e['description'] as String? ?? '';
    final date = _formatDate(e['receipt_date'] as String?);
    final status = e['status'] as String? ?? 'pending';
    final gigId = e['gig_id'] as String?;
    final receiptUrl = e['receipt_url'] as String?;
    final rejectionReason = e['rejection_reason'] as String? ?? '';
    final reiseregningSentAt = e['reiseregning_sent_at'] as String?;

    return GestureDetector(
      onTap: () => _showExpenseDetail(e),
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
          // Date
          SizedBox(
            width: 85,
            child: Text(
              date,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          // Name
          SizedBox(
            width: 140,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Vendor/description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (vendor.isNotEmpty)
                  Text(vendor,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                if (description.isNotEmpty)
                  Text(description,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Gig link indicator
          SizedBox(
            width: 40,
            child: gigId != null
                ? Tooltip(
                    message: 'Koblet til gig',
                    child: Icon(Icons.music_note, size: 16, color: cs.primary),
                  )
                : const SizedBox.shrink(),
          ),
          // Receipt indicator
          SizedBox(
            width: 40,
            child: receiptUrl != null && receiptUrl.isNotEmpty
                ? Tooltip(
                    message: 'Har kvittering',
                    child: Icon(Icons.image, size: 16, color: cs.onSurfaceVariant),
                  )
                : const SizedBox.shrink(),
          ),
          // Amount
          SizedBox(
            width: 100,
            child: Text(
              _formatAmount(amount),
              style: const TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 16),
          // Actions
          if (status == 'pending')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _approve(e),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Godkjenn', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _reject(e),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Avvis', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            )
          else if (status == 'approved')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Godkjent',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                if (reiseregningSentAt != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Sendt til ebilag ${_formatDate(reiseregningSentAt)}',
                    child: const Icon(Icons.email, size: 14, color: Colors.blue),
                  ),
                ],
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                SizedBox(
                  width: 120,
                  child: Text(
                    rejectionReason.isNotEmpty ? rejectionReason : 'Avvist',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
          // Delete button
          IconButton(
            onPressed: () => _deleteExpense(e),
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Slett utlegg',
            color: cs.onSurfaceVariant,
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(32, 32),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett utlegg'),
        content: const Text('Er du sikker på at du vil slette dette utlegget?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _sb.from('expenses').delete().eq('id', expense['id'] as String);
      await _load();
    } catch (e) {
      debugPrint('Delete expense error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved sletting: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Show expense detail dialog with receipt image and approve/reject actions.
  Future<void> _showExpenseDetail(Map<String, dynamic> e) async {
    final profile = e['profiles'] as Map<String, dynamic>?;
    final name = profile?['name'] as String? ?? 'Ukjent';
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    final vendor = e['vendor'] as String? ?? '';
    final description = e['description'] as String? ?? '';
    final date = _formatDate(e['receipt_date'] as String?);
    final status = e['status'] as String? ?? 'pending';
    final receiptPath = e['receipt_url'] as String?;
    final rejectionReason = e['rejection_reason'] as String? ?? '';

    // Get URL for receipt (try signed URL first, fall back to public)
    String? receiptSignedUrl;
    if (receiptPath != null && receiptPath.isNotEmpty) {
      try {
        receiptSignedUrl = await _sb.storage
            .from('expense-receipts')
            .createSignedUrl(receiptPath, 3600);
      } catch (_) {
        try {
          receiptSignedUrl = _sb.storage
              .from('expense-receipts')
              .getPublicUrl(receiptPath);
        } catch (_) {}
      }
      debugPrint('Receipt URL: $receiptSignedUrl (path: $receiptPath)');
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Utlegg fra $name',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Info rows
                  _infoRow('Beløp', _formatAmount(amount), bold: true),
                  if (vendor.isNotEmpty) _infoRow('Leverandør', vendor),
                  if (date.isNotEmpty) _infoRow('Dato', date),
                  if (description.isNotEmpty) _infoRow('Beskrivelse', description),
                  _infoRow('Status', status == 'pending'
                      ? 'Ventende'
                      : status == 'approved'
                          ? 'Godkjent'
                          : 'Avvist'),
                  if (status == 'rejected' && rejectionReason.isNotEmpty)
                    _infoRow('Avvisningsgrunn', rejectionReason),

                  const SizedBox(height: 20),

                  // Receipt image
                  const Text(
                    'Kvittering',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (receiptSignedUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        receiptSignedUrl,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                        errorBuilder: (_, __, ___) => InkWell(
                          onTap: () => launchUrl(Uri.parse(receiptSignedUrl!)),
                          child: Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    receiptPath!.contains('.pdf') ? Icons.picture_as_pdf : Icons.attach_file,
                                    color: Colors.blue,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Åpne kvittering',
                                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Ingen kvittering vedlagt',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),

                  // Actions
                  if (status == 'pending') ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _approve(e);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Godkjenn'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _reject(e);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Avvis'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: bold ? 18 : 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
