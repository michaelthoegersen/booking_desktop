import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for communicating with Tripletex via the `tripletex-proxy` edge function.
class TripletexService {
  static final _sb = Supabase.instance.client;

  /// Generic proxy call to Tripletex API.
  /// Edge function always returns 200 with { ok, data?, error?, details? }.
  static Future<Map<String, dynamic>> _call({
    required String companyId,
    required String method,
    required String path,
    dynamic body,
  }) async {
    final res = await _sb.functions.invoke(
      'tripletex-proxy',
      body: {
        'company_id': companyId,
        'method': method,
        'path': path,
        if (body != null) 'body': body,
      },
    );

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Uventet respons fra proxy: $data');
    }

    // Check for error from edge function
    if (data.containsKey('error')) {
      final details = data['details'];
      final msg = data['error'] as String? ?? 'Ukjent feil';
      // Log full error for debugging
      debugPrint('Tripletex error: $data');
      throw Exception('$msg${details != null ? '\n$details' : ''}');
    }

    // Unwrap the { ok: true, data: ... } envelope
    final inner = data['data'];
    if (inner is Map<String, dynamic>) return inner;
    return data;
  }

  // ── Outgoing invoices ──────────────────────────────────────────────────

  static final _df = DateFormat('yyyy-MM-dd');

  static Future<List<Map<String, dynamic>>> listInvoices(
    String companyId, {
    String? invoiceStatus,
    int count = 100,
  }) async {
    final now = DateTime.now();
    final from = _df.format(now.subtract(const Duration(days: 365)));
    final to = _df.format(now);

    var path = '/invoice?count=$count'
        '&invoiceDateFrom=$from&invoiceDateTo=$to'
        '&fields=id,invoiceNumber,invoiceDate,invoiceDueDate,amount,amountOutstanding,customer(*)';
    if (invoiceStatus != null) {
      path += '&$invoiceStatus=true';
    }
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: path,
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createInvoice(
    String companyId,
    Map<String, dynamic> invoiceData,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'POST',
      path: '/invoice',
      body: invoiceData,
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  // ── Orders ───────────────────────────────────────────────────────────

  /// Create an order with orderLines.
  static Future<Map<String, dynamic>> createOrder(
    String companyId,
    Map<String, dynamic> orderData,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'POST',
      path: '/order',
      body: orderData,
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  /// Create an invoice from an existing order (without sending).
  static Future<Map<String, dynamic>> invoiceOrder(
    String companyId, {
    required int orderId,
    required String invoiceDate,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'PUT',
      path: '/order/$orderId/:invoice'
          '?invoiceDate=$invoiceDate'
          '&sendToCustomer=false',
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  /// Send an existing invoice via EHF or EMAIL.
  static Future<void> sendInvoice(
    String companyId, {
    required int invoiceId,
    required String sendType,
    String? overrideEmail,
  }) async {
    var path = '/invoice/$invoiceId/:send?sendType=$sendType';
    if (sendType == 'EMAIL' && overrideEmail != null && overrideEmail.isNotEmpty) {
      path += '&overrideEmailAddress=${Uri.encodeComponent(overrideEmail)}';
    }
    await _call(
      companyId: companyId,
      method: 'PUT',
      path: path,
    );
  }

  // ── Incoming invoices (bilagsmottak enriched data) ───────────────────

  /// List incoming invoices from bilagsmottak with enriched data
  /// (supplier name, amount, due date, invoice number).
  /// Uses the BETA /incomingInvoice/search endpoint.
  static Future<List<Map<String, dynamic>>> listIncomingInvoices(
    String companyId, {
    String status = 'inbox',
    int count = 200,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/incomingInvoice/search?status=$status&count=$count',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// Get a single incoming invoice with enriched data by voucher ID.
  static Future<Map<String, dynamic>> getIncomingInvoice(
    String companyId,
    int voucherId,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/incomingInvoice/$voucherId',
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  // ── Supplier invoices ──────────────────────────────────────────────────

  /// List supplier invoices with expanded supplier data.
  static Future<List<Map<String, dynamic>>> listSupplierInvoices(
    String companyId, {
    int count = 200,
  }) async {
    final now = DateTime.now();
    final from = _df.format(now.subtract(const Duration(days: 365)));
    final to = _df.format(now);

    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/supplierInvoice?count=$count'
          '&invoiceDateFrom=$from&invoiceDateTo=$to'
          '&fields=*,supplier(*),voucher(*,postings(*))',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// List vouchers in the reception (bilagsmottak) with enriched data.
  static Future<List<Map<String, dynamic>>> listVoucherReception(
    String companyId, {
    int count = 200,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/ledger/voucher/%3EvoucherReception?count=$count'
          '&fields=*,postings(*,supplier(*)),ediDocument(*)',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// Send a voucher from reception to the ledger (bokfør).
  static Future<void> sendVoucherToLedger(
    String companyId,
    int voucherId, {
    int? version,
  }) async {
    var path = '/ledger/voucher/$voucherId/:sendToLedger';
    if (version != null) path += '?version=$version';
    await _call(
      companyId: companyId,
      method: 'PUT',
      path: path,
    );
  }

  /// Get a single voucher with full details including ediDocument.
  static Future<Map<String, dynamic>> getVoucher(
    String companyId,
    int voucherId,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/ledger/voucher/$voucherId?fields=*,postings(*),ediDocument(*)',
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  /// Try to register a voucher reception item as supplier invoice.
  static Future<Map<String, dynamic>> registerVoucherAsSupplierInvoice(
    String companyId, {
    required int voucherId,
    required String invoiceDate,
    String? invoiceNumber,
    int? supplierId,
    String? dueDate,
  }) async {
    final body = <String, dynamic>{
      'invoiceDate': invoiceDate,
      'invoiceDueDate': dueDate ?? invoiceDate,
      'supplier': supplierId != null ? {'id': supplierId} : null,
    };
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      body['invoiceNumber'] = invoiceNumber;
    }
    // Remove null values
    body.removeWhere((k, v) => v == null);

    debugPrint('POST /supplierInvoice body: $body');
    return _call(
      companyId: companyId,
      method: 'POST',
      path: '/supplierInvoice',
      body: body,
    );
  }

  /// Find supplier invoice by voucher ID.
  static Future<List<Map<String, dynamic>>> findSupplierInvoiceByVoucher(
    String companyId,
    int voucherId,
  ) async {
    final now = DateTime.now();
    final from = _df.format(now.subtract(const Duration(days: 365)));
    final to = _df.format(now);
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/supplierInvoice?voucherId=$voucherId'
          '&invoiceDateFrom=$from&invoiceDateTo=$to'
          '&fields=id,invoiceNumber,invoiceDate,invoiceDueDate,amount,supplier(*)',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// Search for supplier by name.
  static Future<List<Map<String, dynamic>>> searchSuppliers(
    String companyId,
    String name,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/supplier?name=${Uri.encodeComponent(name)}&count=5',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// Register payment on a supplier invoice / incoming invoice.
  /// paymentTypeId 0 = use last payment type for this vendor.
  static Future<void> payIncomingInvoice(
    String companyId, {
    required int voucherId,
    required String paymentDate,
    required double amount,
    int paymentTypeId = 0,
  }) async {
    await _call(
      companyId: companyId,
      method: 'POST',
      path: '/supplierInvoice/$voucherId/:addPayment',
      body: {
        'paymentDate': paymentDate,
        'paymentTypeId': paymentTypeId,
        'amount': amount,
      },
    );
  }

  static Future<void> approveSupplierInvoice(
    String companyId,
    int invoiceId,
  ) async {
    await _call(
      companyId: companyId,
      method: 'PUT',
      path: '/supplierInvoice/$invoiceId/:approve',
    );
  }

  /// Register payment on a supplier invoice.
  /// All parameters are query params per the Tripletex API spec.
  /// Set useDefaultPaymentType=true to auto-select the bank payment type
  /// (AutoPay, Nettbank, etc.) configured for this vendor.
  static Future<void> addSupplierPayment(
    String companyId, {
    required int invoiceId,
    required String paymentDate,
    required double amount,
    int paymentTypeId = 0,
    bool useDefaultPaymentType = true,
    String? kidOrReceiverReference,
  }) async {
    var path = '/supplierInvoice/$invoiceId/:addPayment'
        '?paymentType=$paymentTypeId'
        '&amount=$amount'
        '&paymentDate=$paymentDate'
        '&useDefaultPaymentType=$useDefaultPaymentType';
    if (kidOrReceiverReference != null && kidOrReceiverReference.isNotEmpty) {
      path += '&kidOrReceiverReference=${Uri.encodeComponent(kidOrReceiverReference)}';
    }
    debugPrint('addPayment: $path');
    await _call(
      companyId: companyId,
      method: 'POST',
      path: path,
    );
  }

  // ── Ledger: accounts & VAT types ─────────────────────────────────────

  /// List active accounts (kontoplan).
  static Future<List<Map<String, dynamic>>> listAccounts(
    String companyId, {
    int count = 1000,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/ledger/account?count=$count&isActive=true'
          '&fields=id,number,name,vatType(*)',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// List VAT types (MVA-koder).
  static Future<List<Map<String, dynamic>>> listVatTypes(
    String companyId, {
    int count = 100,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/ledger/vatType?count=$count&fields=id,number,name,percentage',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  /// Get a single supplier invoice with full details.
  static Future<Map<String, dynamic>> getSupplierInvoice(
    String companyId,
    int invoiceId,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/supplierInvoice/$invoiceId?fields=*,orderLines(*),voucher(*),supplier(*)',
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  /// Bokfør a supplier invoice by updating its voucher with debit postings
  /// via the standard PUT /ledger/voucher/{id} endpoint (not the broken BETA).
  ///
  /// Flow:
  /// 1. GET the voucher (with existing postings)
  /// 2. GET the supplier invoice (for amount)
  /// 3. Add debit posting to existing postings
  /// 4. PUT voucher with sendToLedger=false
  /// 5. Send to ledger via separate endpoint
  static Future<void> bokforSupplierInvoice(
    String companyId, {
    required int supplierInvoiceId,
    required int voucherId,
    required int accountId,
    int? vatTypeId,
    required String description,
    required String date,
  }) async {
    // Step 1: Get current voucher state (including existing credit postings)
    final voucher = await getVoucher(companyId, voucherId);
    final voucherVersion = (voucher['version'] as num?)?.toInt() ?? 0;
    final voucherDate = voucher['date'] as String? ?? date;

    debugPrint('Voucher $voucherId version=$voucherVersion date=$voucherDate');

    // Step 2: Get invoice amount
    final invoice = await getSupplierInvoice(companyId, supplierInvoiceId);
    final invoiceAmount = (invoice['amount'] as num?)?.toDouble() ?? 0;

    debugPrint('Invoice amount=$invoiceAmount');

    // Step 3: Get supplier's ledger account (accounts payable, e.g. 2400)
    final supplier = invoice['supplier'] as Map<String, dynamic>?;
    final supplierLedgerAccount = supplier?['ledgerAccount'] as Map<String, dynamic>?;
    final supplierAccountId = (supplierLedgerAccount?['id'] as num?)?.toInt();

    debugPrint('Supplier ledger account id=$supplierAccountId');

    if (supplierAccountId == null) {
      throw Exception('Leverandøren mangler hovedbokskonto (leverandørgjeld)');
    }

    // Step 4: Build balanced postings (debit + credit must sum to 0)
    final existingPostings = (voucher['postings'] as List<dynamic>?) ?? [];
    final postings = <Map<String, dynamic>>[];

    // Keep any existing postings
    for (final p in existingPostings) {
      if (p is Map<String, dynamic>) {
        postings.add(Map<String, dynamic>.from(p));
      }
    }

    final grossAmount = invoiceAmount.abs();

    // Credit posting: supplier's ledger account (accounts payable) — negative
    final supplierId = (supplier?['id'] as num?)?.toInt();
    postings.add({
      'row': 1,
      'date': voucherDate,
      'description': description,
      'account': {'id': supplierAccountId},
      if (supplierId != null) 'supplier': {'id': supplierId},
      'amountGross': -grossAmount,
      'amountGrossCurrency': -grossAmount,
    });

    // Debit posting: expense account — positive
    postings.add({
      'row': 2,
      'date': voucherDate,
      'description': description,
      'account': {'id': accountId},
      if (vatTypeId != null) 'vatType': {'id': vatTypeId},
      'amountGross': grossAmount,
      'amountGrossCurrency': grossAmount,
    });

    debugPrint('PUT voucher postings count=${postings.length}');
    debugPrint('New debit posting: account=$accountId, amountGross=${invoiceAmount.abs()}');

    // Step 4: Update voucher AND send to ledger in one call
    await _call(
      companyId: companyId,
      method: 'PUT',
      path: '/ledger/voucher/$voucherId?sendToLedger=true',
      body: {
        'id': voucherId,
        'version': voucherVersion,
        'date': voucherDate,
        'postings': postings,
      },
    );
    debugPrint('Voucher $voucherId updated and sent to ledger');
  }

  /// List payment types.
  static Future<List<Map<String, dynamic>>> listPaymentTypes(
    String companyId, {
    int count = 50,
  }) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/ledger/paymentTypeOut?count=$count&fields=id,description,showIncomingInvoice,isInactive',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  // ── Customers ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchCustomers(
    String companyId,
    String name,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/customer?name=${Uri.encodeComponent(name)}&count=10',
    );
    final values = data['values'] as List<dynamic>? ?? [];
    return values.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createCustomer(
    String companyId,
    Map<String, dynamic> customerData,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'POST',
      path: '/customer',
      body: customerData,
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  /// Update a customer's settings (e.g. invoiceSendMethod).
  static Future<Map<String, dynamic>> updateCustomer(
    String companyId,
    int customerId,
    Map<String, dynamic> updates,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'PUT',
      path: '/customer/$customerId',
      body: {'id': customerId, ...updates},
    );
    return data['value'] as Map<String, dynamic>? ?? data;
  }

  static Future<Map<String, dynamic>> findOrCreateCustomer(
    String companyId, {
    required String name,
    String? orgNr,
    String? email,
  }) async {
    // 1. If orgNr is provided, search by organization number (unique identifier)
    if (orgNr != null && orgNr.isNotEmpty) {
      try {
        final data = await _call(
          companyId: companyId,
          method: 'GET',
          path: '/customer?organizationNumber=${Uri.encodeComponent(orgNr)}&count=1',
        );
        final values = data['values'] as List<dynamic>? ?? [];
        if (values.isNotEmpty) {
          final found = values.first as Map<String, dynamic>;
          debugPrint('Found customer by orgNr: ${found['name']} (id=${found['id']})');
          return found;
        }
      } catch (e) {
        debugPrint('Customer search by orgNr failed: $e');
      }
    }

    // 2. Search by name — require exact match (case-insensitive)
    try {
      final existing = await searchCustomers(companyId, name);
      final nameLower = name.toLowerCase().trim();
      for (final c in existing) {
        final cName = (c['name'] as String? ?? '').toLowerCase().trim();
        if (cName == nameLower) {
          debugPrint('Found exact customer match: ${c['name']} (id=${c['id']})');
          return c;
        }
      }
    } catch (e) {
      debugPrint('Customer search by name failed: $e');
    }

    // 3. No match — create new customer
    debugPrint('Creating new Tripletex customer: $name');
    return createCustomer(companyId, {
      'name': name,
      if (orgNr != null && orgNr.isNotEmpty) 'organizationNumber': orgNr,
      if (email != null && email.isNotEmpty) 'email': email,
      'isCustomer': true,
    });
  }

  // ── Documents ───────────────────────────────────────────────────────────

  /// Download a document/attachment from Tripletex and save to temp dir.
  /// Returns the local file path. Opens the file with the system viewer.
  static Future<String> downloadAndOpenDocument(
    String companyId,
    int documentId,
  ) async {
    final data = await _call(
      companyId: companyId,
      method: 'GET',
      path: '/document/$documentId/content',
    );

    if (data['_binary'] != true) {
      throw Exception('Uventet respons — ikke binær');
    }

    final base64Data = data['base64'] as String;
    final fileName = data['fileName'] as String? ?? 'document.pdf';
    final bytes = base64Decode(base64Data);

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    // Open with system default viewer
    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else if (Platform.isWindows) {
      await Process.run('start', ['', file.path], runInShell: true);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
    }

    return file.path;
  }
}
