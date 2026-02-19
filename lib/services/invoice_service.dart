import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/invoice.dart';
import '../models/offer_draft.dart';
import '../models/round_calc_result.dart';

class InvoiceService {
  static final _client = Supabase.instance.client;

  // ============================================================
  // AUTO-NUMBER GENERATION
  // ============================================================

  static Future<String> generateInvoiceNumber() async {
    final year = DateTime.now().year;

    final rows = await _client
        .from('invoices')
        .select('invoice_number')
        .like('invoice_number', '$year-%')
        .order('invoice_number', ascending: false)
        .limit(1);

    if ((rows as List).isEmpty) return '$year-001';

    final last = int.parse(
      (rows.first['invoice_number'] as String).split('-').last,
    );

    return '$year-${(last + 1).toString().padLeft(3, '0')}';
  }

  // ============================================================
  // CREATE FROM OFFER
  // ============================================================

  static Future<Invoice> createFromOffer({
    required OfferDraft offer,
    required Map<int, RoundCalcResult> roundCalc,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required DateTime dueDate,
    required String bankAccount,
    required String paymentRef,
    required double totalExclVat,
    required Map<String, double> vatBreakdown,
    required double totalInclVat,
    required Map<String, double> countryKm,
    String? offerId,
  }) async {
    final user = _client.auth.currentUser;

    // Build per-round summaries
    final rounds = <InvoiceRound>[];

    for (int i = 0; i < offer.rounds.length; i++) {
      final round = offer.rounds[i];
      final result = roundCalc[i];

      if (round.entries.isEmpty || result == null) continue;
      if (result.totalCost <= 0) continue;

      rounds.add(InvoiceRound(
        startDate: round.entries.first.date,
        endDate: round.entries.last.date,
        totalCost: result.totalCost,
        label: 'Round ${i + 1}',
      ));
    }

    final invoice = Invoice(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      dueDate: dueDate,
      company: offer.company,
      contact: offer.contact,
      phone: offer.phone,
      email: offer.email,
      production: offer.production,
      rounds: rounds,
      totalExclVat: totalExclVat,
      vatBreakdown: vatBreakdown,
      totalInclVat: totalInclVat,
      countryKm: countryKm,
      bankAccount: bankAccount,
      paymentRef: paymentRef,
      status: 'unpaid',
      offerId: offerId,
      userId: user?.id,
    );

    final res = await _client
        .from('invoices')
        .insert(invoice.toJson())
        .select()
        .single();

    return Invoice.fromJson(Map<String, dynamic>.from(res));
  }

  // ============================================================
  // LIST
  // ============================================================

  static Future<List<Invoice>> listInvoices() async {
    final res = await _client
        .from('invoices')
        .select()
        .order('invoice_number', ascending: false);

    return (res as List)
        .map((row) => Invoice.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ============================================================
  // UPDATE STATUS
  // ============================================================

  static Future<void> updateStatus(String id, String status) async {
    await _client
        .from('invoices')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // ============================================================
  // DELETE
  // ============================================================

  static Future<void> deleteInvoice(String id) async {
    await _client.from('invoices').delete().eq('id', id);
  }
}
