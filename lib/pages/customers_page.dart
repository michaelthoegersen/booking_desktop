import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/new_company_dialog.dart';
import '../widgets/production_dialog.dart';
import '../widgets/send_invoice_dialog.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/pdf_export_service.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});


  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final SupabaseClient _client = Supabase.instance.client;

  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _debounce;
Future<Map<String, dynamic>> _loadAllForPdf() async {

  final companies = await _client
      .from('companies')
      .select()
      .order('name');

  final contacts = await _client
      .from('contacts')
      .select();

  final productions = await _client
      .from('productions')
      .select();

  return {
    "companies": List<Map<String,dynamic>>.from(companies),
    "contacts": List<Map<String,dynamic>>.from(contacts),
    "productions": List<Map<String,dynamic>>.from(productions),
  };
}
  Future<void> _exportPdf() async {
  final pdf = pw.Document();

  // Hent ALT direkte fra Supabase (ikke bare valgt company)
  final companies = await _client
      .from('companies')
      .select()
      .order('name');

  final contacts = await _client.from('contacts').select();
  final productions = await _client.from('productions').select();

  pdf.addPage(
    pw.MultiPage(
      build: (context) {
        return companies.map<pw.Widget>((c) {

          final cid = c['id'];

          final companyContacts = contacts
              .where((x) => x['company_id'] == cid)
              .toList();

          final companyProductions = productions
              .where((x) => x['company_id'] == cid)
              .toList();

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // COMPANY NAME
                pw.Text(
                  c['name'] ?? '',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),

                pw.SizedBox(height: 6),

                // CONTACTS
                if (companyContacts.isNotEmpty) ...[
                  pw.Text(
                    "Contacts",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),

                  ...companyContacts.map((co) {
                    return pw.Text(
                      "${co['name'] ?? ''}   ${co['phone'] ?? ''}   ${co['email'] ?? ''}",
                    );
                  }),
                  pw.SizedBox(height: 6),
                ],

                // PRODUCTIONS
                if (companyProductions.isNotEmpty) ...[
                  pw.Text(
                    "Productions",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),

                  ...companyProductions.map((p) {
                    return pw.Text(p['name'] ?? '');
                  }),
                ],
              ],
            ),
          );
        }).toList();
      },
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => pdf.save(),
  );
}

  // DATA
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _productions = [];

  Map<String, dynamic>? _selectedCompany;

  bool _loadingCompanies = false;
  bool _loadingDetails = false;

  // ==================================================
  // INIT
  // ==================================================
  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ==================================================
  // LOAD COMPANIES (SEARCH + AUTOSELECT)
  // ==================================================
  Future<void> _loadCompanies({String? search}) async {
    setState(() => _loadingCompanies = true);

    try {
      var query = _client.from('companies').select();

      final q = search?.trim() ?? '';

      if (q.isNotEmpty) {
        query = query.ilike('name', '%$q%');
      }

      final res = await query.order('name');

      if (!mounted) return;

      final list = List<Map<String, dynamic>>.from(res);

      setState(() {
        _companies = list;
      });

      // Auto-select
      if (list.isNotEmpty) {
        final stillExists = _selectedCompany != null &&
            list.any((c) => c['id'] == _selectedCompany!['id']);

        if (!stillExists) {
          final first = list.first;

          setState(() {
            _selectedCompany = first;
          });

          await _loadDetails(first['id']);
        }
      } else {
        setState(() {
          _selectedCompany = null;
          _contacts.clear();
          _productions.clear();
        });
      }
    } catch (e) {
      debugPrint("LOAD COMPANIES ERROR: $e");
    } finally {
      if (mounted) {
        setState(() => _loadingCompanies = false);
      }
    }
  }

  // ==================================================
  // LOAD DETAILS
  // ==================================================
  Future<void> _loadDetails(String companyId) async {
    setState(() => _loadingDetails = true);

    try {
      final contacts = await _client
          .from('contacts')
          .select()
          .eq('company_id', companyId)
          .order('name');

      final productions = await _client
          .from('productions')
          .select()
          .eq('company_id', companyId)
          .order('name');

      if (!mounted) return;

      setState(() {
        _contacts = List<Map<String, dynamic>>.from(contacts);
        _productions = List<Map<String, dynamic>>.from(productions);
      });
    } finally {
      if (mounted) {
        setState(() => _loadingDetails = false);
      }
    }
  }

  // ==================================================
  // SEARCH
  // ==================================================
  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadCompanies(search: value);
    });
  }

  // ==================================================
  // COMPANY CRUD
  // ==================================================
  Future<void> _createCompany() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const NewCompanyDialog(),
    );

    if (created != true) return;

    await _loadCompanies();
  }

  Future<void> _editCompany() async {
    if (_selectedCompany == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditCompanyDialog(company: _selectedCompany!),
    );

    if (saved != true) return;

    final updated = await _client
        .from('companies')
        .select()
        .eq('id', _selectedCompany!['id'])
        .single();

    setState(() => _selectedCompany = updated);
    await _loadCompanies();
  }

  Future<void> _deleteCompany() async {
    if (_selectedCompany == null) return;

    final name = _selectedCompany!['name'];
    final id = _selectedCompany!['id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Delete company"),
          content: Text(
            'Delete "$name"?\n\nAll contacts and productions will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await _client.from('contacts').delete().eq('company_id', id);
    await _client.from('productions').delete().eq('company_id', id);
    await _client.from('companies').delete().eq('id', id);

    setState(() {
      _selectedCompany = null;
      _contacts.clear();
      _productions.clear();
    });

    await _loadCompanies();
  }

  // ==================================================
  // CONTACT CRUD
  // ==================================================
  Future<void> _createContact() async {
    if (_selectedCompany == null) return;

    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();

    final ok = await _showContactDialog(name, phone, email);

    if (!ok) return;

    await _client.from('contacts').insert({
      'company_id': _selectedCompany!['id'],
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
    });

    _loadDetails(_selectedCompany!['id']);
  }

  Future<void> _editContact(Map<String, dynamic> c) async {
    final name = TextEditingController(text: c['name']);
    final phone = TextEditingController(text: c['phone']);
    final email = TextEditingController(text: c['email']);

    final ok = await _showContactDialog(name, phone, email);

    if (!ok) return;

    await _client.from('contacts').update({
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
    }).eq('id', c['id']);

    _loadDetails(_selectedCompany!['id']);
  }

  // ==================================================
  // PRODUCTION CRUD
  // ==================================================
  Future<void> _createProduction() async {
    if (_selectedCompany == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductionDialog(companyId: _selectedCompany!['id']),
    );

    if (saved != true) return;
    _loadDetails(_selectedCompany!['id']);
  }

  Future<void> _editProduction(Map<String, dynamic> p) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductionDialog(
        companyId: _selectedCompany!['id'],
        existing: p,
      ),
    );

    if (saved != true) return;
    _loadDetails(_selectedCompany!['id']);
  }

  // ==================================================
  // SEND INVOICE DETAILS
  // ==================================================
  Future<void> _sendInvoiceDetails({
    required Map<String, dynamic> company,
    Map<String, dynamic>? production,
  }) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SendInvoiceDialog(
        company: company,
        production: production,
      ),
    );
  }

  // ==================================================
  // DIALOGS
  // ==================================================
  Future<String?> _showTextDialog({
    required String title,
    required String label,
    required TextEditingController controller,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, controller.text.trim());
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showContactDialog(
    TextEditingController name,
    TextEditingController phone,
    TextEditingController email,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Contact"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: "Name")),
              TextField(controller: phone, decoration: const InputDecoration(labelText: "Phone")),
              TextField(controller: email, decoration: const InputDecoration(labelText: "Email")),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    ).then((v) => v ?? false);
  }

  // ==================================================
  // UI
  // ==================================================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceVariant,
      child: Row(
        children: [
          // LEFT
          SizedBox(
            width: 340,
            child: Card(
              margin: const EdgeInsets.all(12),
              elevation: 2,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildSearch(),
                  Expanded(child: _buildCompanies()),
                ],
              ),
            ),
          ),

          // RIGHT
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              elevation: 2,
              child: _buildDetails(),
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // LEFT
  // ==================================================
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
  children: [
    const Text(
      "Companies",
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    ),
    const Spacer(),

    IconButton(
  icon: const Icon(Icons.picture_as_pdf),
  onPressed: () async {

  debugPrint("PDF CLICKED");

  final data = await _loadAllForPdf();

  await PdfExportService.exportCustomers(
  companies: List<Map<String,dynamic>>.from(data["companies"]),
  contacts: List<Map<String,dynamic>>.from(data["contacts"]),
  productions: List<Map<String,dynamic>>.from(data["productions"]),
);
}
),

    IconButton(
      onPressed: _createCompany,
      icon: const Icon(Icons.add),
    ),
  ],
),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: "Search...",
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildCompanies() {
    if (_loadingCompanies) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _companies.length,
      itemBuilder: (_, i) {
        final c = _companies[i];

        final selected = _selectedCompany?['id'] == c['id'];

        return ListTile(
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer,
          title: Text(c['name'] ?? ''),
          onTap: () {
            setState(() => _selectedCompany = c);
            _loadDetails(c['id']);
          },
        );
      },
    );
  }

  // ==================================================
  // RIGHT
  // ==================================================
  Widget _buildDetails() {
    if (_selectedCompany == null) {
      return const Center(child: Text("Select company"));
    }

    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _buildCompanyInfo(),
        const SizedBox(height: 24),
        _buildContacts(),
        const SizedBox(height: 24),
        _buildProductions(),
      ],
    );
  }

  Widget _buildCompanyInfo() {
    final c = _selectedCompany!;
    final cs = Theme.of(context).colorScheme;

    // Build address string
    String _addressLine() {
      final parts = <String>[];
      if ((c['address'] ?? '').isNotEmpty) parts.add(c['address']);
      final city = [
        if ((c['postal_code'] ?? '').isNotEmpty) c['postal_code'],
        if ((c['city'] ?? '').isNotEmpty) c['city'],
      ].join(' ');
      if (city.isNotEmpty) parts.add(city);
      if ((c['country'] ?? '').isNotEmpty) parts.add(c['country']);
      return parts.join(', ');
    }

    String _invoiceAddressLine() {
      final parts = <String>[];
      if ((c['invoice_address'] ?? '').isNotEmpty) parts.add(c['invoice_address']);
      final city = [
        if ((c['invoice_postal_code'] ?? '').isNotEmpty) c['invoice_postal_code'],
        if ((c['invoice_city'] ?? '').isNotEmpty) c['invoice_city'],
      ].join(' ');
      if (city.isNotEmpty) parts.add(city);
      if ((c['invoice_country'] ?? '').isNotEmpty) parts.add(c['invoice_country']);
      return parts.join(', ');
    }

    final hasSeparateInvoice = c['separate_invoice_recipient'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name row + actions
          Row(
            children: [
              Expanded(
                child: Text(
                  c['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _sendInvoiceDetails(company: c),
                icon: const Icon(Icons.send),
                tooltip: "Send invoice details",
              ),
              IconButton(
                onPressed: _editCompany,
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                onPressed: _deleteCompany,
                icon: const Icon(Icons.delete),
                color: Colors.red,
              ),
            ],
          ),

          // Org nr
          if ((c['org_nr'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "Org.nr: ${c['org_nr']}",
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],

          // Address
          if (_addressLine().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _addressLine(),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],

          // Separate invoice recipient block
          if (hasSeparateInvoice) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.secondary.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Invoice recipient",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.secondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if ((c['invoice_name'] ?? '').isNotEmpty)
                    Text(
                      c['invoice_name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if ((c['invoice_org_nr'] ?? '').isNotEmpty)
                    Text("Org.nr: ${c['invoice_org_nr']}"),
                  if (_invoiceAddressLine().isNotEmpty)
                    Text(_invoiceAddressLine()),
                  if ((c['invoice_email'] ?? '').isNotEmpty)
                    Text("E-post: ${c['invoice_email']}"),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContacts() {
    return _sectionCard(
      title: "Contacts",
      onAdd: _createContact,
      children: _contacts.isEmpty
          ? [const Text("No contacts")]
          : _contacts.map((c) {
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(c['name'] ?? ''),
                subtitle:
                    Text("${c['phone'] ?? ''} · ${c['email'] ?? ''}"),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editContact(c),
                ),
              );
            }).toList(),
    );
  }

  Widget _buildProductions() {
    final cs = Theme.of(context).colorScheme;

    return _sectionCard(
      title: "Productions",
      onAdd: _createProduction,
      children: _productions.isEmpty
          ? [const Text("No productions")]
          : _productions.map((p) {
              final hasSeparateInvoice =
                  p['separate_invoice_recipient'] == true;

              Widget? invoiceSubtitle;
              if (hasSeparateInvoice) {
                final parts = <String>[];
                if ((p['invoice_name'] ?? '').isNotEmpty)
                  parts.add(p['invoice_name']);
                if ((p['invoice_org_nr'] ?? '').isNotEmpty)
                  parts.add("Org.nr: ${p['invoice_org_nr']}");

                final addrParts = <String>[];
                if ((p['invoice_address'] ?? '').isNotEmpty)
                  addrParts.add(p['invoice_address']);
                final city = [
                  if ((p['invoice_postal_code'] ?? '').isNotEmpty)
                    p['invoice_postal_code'],
                  if ((p['invoice_city'] ?? '').isNotEmpty) p['invoice_city'],
                ].join(' ');
                if (city.isNotEmpty) addrParts.add(city);
                if ((p['invoice_country'] ?? '').isNotEmpty)
                  addrParts.add(p['invoice_country']);
                if (addrParts.isNotEmpty) parts.add(addrParts.join(', '));
                if ((p['invoice_email'] ?? '').isNotEmpty)
                  parts.add(p['invoice_email']);

                invoiceSubtitle = Container(
                  margin: const EdgeInsets.only(top: 4, left: 56),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: cs.secondary.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Invoice recipient",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cs.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        parts.join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.movie),
                    ),
                    title: Text(p['name'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.send),
                          tooltip: "Send invoice details",
                          onPressed: () => _sendInvoiceDetails(
                            company: _selectedCompany!,
                            production: p,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editProduction(p),
                        ),
                      ],
                    ),
                  ),
                  if (invoiceSubtitle != null) ...[
                    invoiceSubtitle,
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }).toList(),
    );
  }

  Widget _sectionCard({
    required String title,
    required VoidCallback onAdd,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),

            const Divider(),

            ...children,
          ],
        ),
      ),
    );
  }
}