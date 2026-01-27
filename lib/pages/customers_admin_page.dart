import 'package:flutter/material.dart';

import '../services/customers_service.dart';

class CustomersAdminPage extends StatefulWidget {
  const CustomersAdminPage({super.key});

  @override
  State<CustomersAdminPage> createState() => _CustomersAdminPageState();
}

class _CustomersAdminPageState extends State<CustomersAdminPage> {
  final _service = CustomersService();

  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _productions = [];

  Map<String, dynamic>? _selectedCompany;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  // -----------------------------------
  // LOAD COMPANIES
  // -----------------------------------
  Future<void> _loadCompanies() async {
    setState(() => _loading = true);

    try {
      final res = await _service.getCompanies();

      setState(() {
        _companies = res;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // -----------------------------------
  // SELECT COMPANY
  // -----------------------------------
  Future<void> _selectCompany(Map<String, dynamic> company) async {
    setState(() {
      _selectedCompany = company;
      _contacts = [];
      _productions = [];
    });

    final contacts =
        await _service.getContacts(company['id']);

    final productions =
        await _service.getProductions(company['id']);

    setState(() {
      _contacts = contacts;
      _productions = productions;
    });
  }

  // -----------------------------------
  // UI
  // -----------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customers admin"),
        actions: [
          IconButton(
            onPressed: _loadCompanies,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),

      body: Row(
        children: [
          // ===================================
          // LEFT – COMPANIES
          // ===================================
          SizedBox(
            width: 320,
            child: _buildCompanies(),
          ),

          const VerticalDivider(width: 1),

          // ===================================
          // RIGHT – DETAILS
          // ===================================
          Expanded(
            child: _buildDetails(),
          ),
        ],
      ),
    );
  }

  // -----------------------------------
  // COMPANIES LIST
  // -----------------------------------
  Widget _buildCompanies() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _companies.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final c = _companies[i];

        final selected =
            _selectedCompany?['id'] == c['id'];

        return ListTile(
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer,

          title: Text(c['name'] ?? ''),

          onTap: () => _selectCompany(c),
        );
      },
    );
  }

  // -----------------------------------
  // DETAILS PANEL
  // -----------------------------------
  Widget _buildDetails() {
    if (_selectedCompany == null) {
      return const Center(
        child: Text("Select a company"),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------- COMPANY
          Text(
            _selectedCompany!['name'],
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),

          // ---------------- CONTACTS
          Text(
            "Contacts",
            style: Theme.of(context).textTheme.titleMedium,
          ),

          const SizedBox(height: 6),

          Expanded(
            child: ListView(
              children: [
                ..._contacts.map(_contactTile),
                const SizedBox(height: 12),

                Text(
                  "Productions",
                  style:
                      Theme.of(context).textTheme.titleMedium,
                ),

                const SizedBox(height: 6),

                ..._productions.map(_productionTile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------
  // CONTACT TILE
  // -----------------------------------
  Widget _contactTile(Map<String, dynamic> c) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),

        title: Text(c['name'] ?? ''),

        subtitle: Text(
          '${c['email'] ?? ''} • ${c['phone'] ?? ''}',
        ),
      ),
    );
  }

  // -----------------------------------
  // PRODUCTION TILE
  // -----------------------------------
  Widget _productionTile(Map<String, dynamic> p) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.movie),

        title: Text(p['name'] ?? ''),
      ),
    );
  }
}