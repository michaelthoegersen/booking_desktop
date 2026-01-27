import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final SupabaseClient _client = Supabase.instance.client;

  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _debounce;

  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _productions = [];

  Map<String, dynamic>? _selectedCompany;

  bool _loadingCompanies = false;
  bool _loadingDetails = false;

  // --------------------------------------------------
  // INIT
  // --------------------------------------------------
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

  // --------------------------------------------------
  // LOAD COMPANIES (WITH OPTIONAL SEARCH)
  // --------------------------------------------------
  Future<void> _loadCompanies({String? search}) async {
    setState(() => _loadingCompanies = true);

    try {
      final query = _client.from('companies').select();

      if (search != null && search.trim().isNotEmpty) {
        query.ilike('name', '%${search.trim()}%');
      }

      final res = await query.order('name');

      if (!mounted) return;

      setState(() {
        _companies = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('LOAD COMPANIES ERROR: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingCompanies = false);
      }
    }
  }

  // --------------------------------------------------
  // LOAD DETAILS
  // --------------------------------------------------
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
    } catch (e) {
      debugPrint('LOAD DETAILS ERROR: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingDetails = false);
      }
    }
  }

  // --------------------------------------------------
  // SEARCH HANDLER (DEBOUNCE)
  // --------------------------------------------------
  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _selectedCompany = null;
      _contacts = [];
      _productions = [];

      _loadCompanies(search: value);
    });
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // ==================================================
        // LEFT: COMPANIES
        // ==================================================
        SizedBox(
          width: 340,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                _buildCompaniesHeader(),
                _buildSearch(),
                Expanded(child: _buildCompaniesList()),
              ],
            ),
          ),
        ),

        // ==================================================
        // RIGHT: DETAILS
        // ==================================================
        Expanded(
          child: _buildDetails(),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // HEADER
  // --------------------------------------------------
  Widget _buildCompaniesHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          const Text(
            "Companies",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              _searchCtrl.clear();
              _loadCompanies();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // SEARCH FIELD
  // --------------------------------------------------
  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: "Search company...",
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // COMPANIES LIST
  // --------------------------------------------------
  Widget _buildCompaniesList() {
    if (_loadingCompanies) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_companies.isEmpty) {
      return const Center(child: Text("No companies found"));
    }

    return ListView.builder(
      itemCount: _companies.length,
      itemBuilder: (_, i) {
        final c = _companies[i];
        final selected = _selectedCompany?['id'] == c['id'];

        return ListTile(
          title: Text(
            c['name'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer,
          onTap: () {
            setState(() {
              _selectedCompany = c;
            });

            _loadDetails(c['id']);
          },
        );
      },
    );
  }

  // --------------------------------------------------
  // DETAILS PANEL
  // --------------------------------------------------
  Widget _buildDetails() {
    if (_selectedCompany == null) {
      return const Center(
        child: Text("Select a company"),
      );
    }

    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: ListView(
        children: [
          _buildCompanyInfo(),
          const SizedBox(height: 24),

          _buildContacts(),
          const SizedBox(height: 24),

          _buildProductions(),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // COMPANY INFO
  // --------------------------------------------------
  Widget _buildCompanyInfo() {
    return Text(
      _selectedCompany!['name'] ?? '',
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  // --------------------------------------------------
  // CONTACTS
  // --------------------------------------------------
  Widget _buildContacts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Contacts",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),

        if (_contacts.isEmpty)
          const Text("No contacts"),

        ..._contacts.map((c) {
          return Card(
            child: ListTile(
              title: Text(c['name'] ?? ''),
              subtitle: Text(
                "${c['phone'] ?? ''} · ${c['email'] ?? ''}",
              ),
              leading: const Icon(Icons.person),
            ),
          );
        }),
      ],
    );
  }

  // --------------------------------------------------
  // PRODUCTIONS
  // --------------------------------------------------
  Widget _buildProductions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Productions",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),

        if (_productions.isEmpty)
          const Text("No productions"),

        ..._productions.map((p) {
          return Card(
            child: ListTile(
              title: Text(p['name'] ?? ''),
              leading: const Icon(Icons.movie),
            ),
          );
        }),
      ],
    );
  }
}