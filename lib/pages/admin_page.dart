import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/brreg_service.dart';
import '../services/platform_admin_service.dart';

/// Platform admin page — create & list tenant companies.
///
/// Tenants are companies with `owner_company_id IS NULL`. Only users with
/// `profiles.is_platform_admin = TRUE` can access this page (guarded both
/// in the sidebar and via RLS on the server).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final SupabaseClient _sb = Supabase.instance.client;

  bool _loading = true;
  bool _forbidden = false;
  List<Map<String, dynamic>> _tenants = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await platformAdminNotifier.refresh();
    if (!platformAdminNotifier.value) {
      if (mounted) {
        setState(() {
          _forbidden = true;
          _loading = false;
        });
      }
      return;
    }
    await _loadTenants();
  }

  Future<void> _loadTenants() async {
    setState(() => _loading = true);
    try {
      final rows = await _sb
          .from('companies')
          .select('id, name, org_nr, city, country, created_at')
          .filter('owner_company_id', 'is', null)
          .order('name');
      if (!mounted) return;
      setState(() {
        _tenants = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Admin load tenants error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateTenantDialog(),
    );
    if (result == null) return;

    if (!mounted) return;
    final createdUser = result['created_user'] as Map<String, dynamic>?;
    if (createdUser != null) {
      // Show temporary password so admin can forward it
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Brukeren ble opprettet'),
          content: SelectableText(
            'Epost: ${createdUser['email']}\n'
            'Midlertidig passord: ${createdUser['temp_password']}\n\n'
            'Send dette til brukeren — de bør bytte passord ved første pålogging.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    await _loadTenants();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_forbidden) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 64, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                'Kun plattform-administratorer har tilgang til denne siden.',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_rounded, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Plattformadministrasjon',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Nytt tenant-selskap'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Selskaper i TourFlow-plattformen (${_tenants.length})',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: ListView.separated(
                  itemCount: _tenants.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final t = _tenants[i];
                    final orgNr = t['org_nr'] as String?;
                    final city = t['city'] as String?;
                    final country = t['country'] as String?;
                    final subtitle = [
                      if (orgNr != null && orgNr.isNotEmpty) 'Org.nr $orgNr',
                      if (city != null && city.isNotEmpty) city,
                      if (country != null && country.isNotEmpty) country,
                    ].join(' · ');
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.business),
                      ),
                      title: Text(
                        t['name'] as String? ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      trailing: Text(
                        (t['id'] as String).substring(0, 8),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CREATE DIALOG
// ════════════════════════════════════════════════════════════════════════════

class _CreateTenantDialog extends StatefulWidget {
  const _CreateTenantDialog();

  @override
  State<_CreateTenantDialog> createState() => _CreateTenantDialogState();
}

enum _FirstAdminMode { self, newUser, none }

class _CreateTenantDialogState extends State<_CreateTenantDialog> {
  final _nameCtrl = TextEditingController();
  final _orgNrCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  String _appMode = 'css';

  _FirstAdminMode _firstAdminMode = _FirstAdminMode.self;
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPhoneCtrl = TextEditingController();

  final _brregCtrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<BrregCompany> _brregResults = [];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orgNrCtrl.dispose();
    _addressCtrl.dispose();
    _postalCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPhoneCtrl.dispose();
    _brregCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onBrregSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _brregResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final cleaned = q.replaceAll(RegExp(r'\s'), '');
        if (RegExp(r'^\d{9}$').hasMatch(cleaned)) {
          final one = await BrregService.lookup(cleaned);
          if (mounted) {
            setState(() => _brregResults = one != null ? [one] : []);
          }
        } else {
          final list = await BrregService.search(q);
          if (mounted) setState(() => _brregResults = list);
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _applyBrreg(BrregCompany c) {
    setState(() {
      _nameCtrl.text = c.name;
      _orgNrCtrl.text = c.orgNr;
      _addressCtrl.text = c.address ?? '';
      _postalCtrl.text = c.postalCode ?? '';
      _cityCtrl.text = c.city ?? '';
      _countryCtrl.text = c.country ?? '';
      _brregCtrl.clear();
      _brregResults = [];
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Selskapsnavn er påkrevd');
      return;
    }

    Map<String, dynamic> firstAdmin;
    switch (_firstAdminMode) {
      case _FirstAdminMode.self:
        firstAdmin = {'mode': 'self'};
        break;
      case _FirstAdminMode.none:
        firstAdmin = {'mode': 'none'};
        break;
      case _FirstAdminMode.newUser:
        final adminName = _adminNameCtrl.text.trim();
        final adminEmail = _adminEmailCtrl.text.trim();
        if (adminName.isEmpty || adminEmail.isEmpty) {
          setState(() => _error = 'Navn og epost på første admin er påkrevd');
          return;
        }
        firstAdmin = {
          'mode': 'new',
          'name': adminName,
          'email': adminEmail,
          if (_adminPhoneCtrl.text.trim().isNotEmpty)
            'phone': _adminPhoneCtrl.text.trim(),
        };
        break;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final res = await sb.functions.invoke(
        'create-tenant-company',
        body: {
          'name': name,
          'org_nr': _orgNrCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'postal_code': _postalCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'country': _countryCtrl.text.trim(),
          'app_mode': _appMode,
          'first_admin': firstAdmin,
        },
      );

      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      if (data is! Map<String, dynamic> || data['ok'] != true) {
        throw 'Uventet svar fra server: $data';
      }
      if (!mounted) return;
      Navigator.pop(context, Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nytt tenant-selskap',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Oppretter et helt nytt selskap i TourFlow-plattformen.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brreg
                      TextField(
                        controller: _brregCtrl,
                        onChanged: _onBrregSearch,
                        decoration: InputDecoration(
                          labelText: 'Søk i Brreg (navn eller org.nr)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (_brregResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _brregResults.length,
                            itemBuilder: (_, i) {
                              final c = _brregResults[i];
                              return ListTile(
                                dense: true,
                                title: Text(c.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${c.orgNr} · ${c.city ?? ''}'),
                                onTap: () => _applyBrreg(c),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Selskapsnavn *',
                          prefixIcon: Icon(Icons.apartment),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orgNrCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Org.nr',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Adresse',
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _postalCtrl,
                              decoration: const InputDecoration(labelText: 'Postnr'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cityCtrl,
                              decoration: const InputDecoration(labelText: 'Sted'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Land',
                          prefixIcon: Icon(Icons.flag),
                        ),
                      ),

                      const Divider(height: 32),

                      // App mode
                      const Text('Portal',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'css', label: Text('Logistics (CSS)')),
                          ButtonSegment(value: 'management', label: Text('Management')),
                        ],
                        selected: {_appMode},
                        onSelectionChanged: (s) =>
                            setState(() => _appMode = s.first),
                      ),

                      const Divider(height: 32),

                      // First admin
                      const Text('Første admin-bruker',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      RadioListTile<_FirstAdminMode>(
                        value: _FirstAdminMode.self,
                        groupValue: _firstAdminMode,
                        onChanged: (v) => setState(() => _firstAdminMode = v!),
                        title: const Text('Sett meg selv som admin'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<_FirstAdminMode>(
                        value: _FirstAdminMode.newUser,
                        groupValue: _firstAdminMode,
                        onChanged: (v) => setState(() => _firstAdminMode = v!),
                        title: const Text('Opprett ny bruker'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<_FirstAdminMode>(
                        value: _FirstAdminMode.none,
                        groupValue: _firstAdminMode,
                        onChanged: (v) => setState(() => _firstAdminMode = v!),
                        title: const Text('Ingen — legg til senere'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),

                      if (_firstAdminMode == _FirstAdminMode.newUser) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _adminNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Navn *',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _adminEmailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Epost *',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _adminPhoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Telefon',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Avbryt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Opprett'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
