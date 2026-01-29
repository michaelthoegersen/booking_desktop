import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewCompanyDialog extends StatefulWidget {
  const NewCompanyDialog({super.key});

  @override
  State<NewCompanyDialog> createState() => _NewCompanyDialogState();
}

class _NewCompanyDialogState extends State<NewCompanyDialog> {
  final SupabaseClient _client = Supabase.instance.client;

  // Controllers
  final _companyCtrl = TextEditingController();

  final _contactNameCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  final _productionCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _companyCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactEmailCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _productionCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // SAVE EVERYTHING
  // --------------------------------------------------
  Future<void> _save() async {
    final company = _companyCtrl.text.trim();
    final contactName = _contactNameCtrl.text.trim();
    final email = _contactEmailCtrl.text.trim();
    final phone = _contactPhoneCtrl.text.trim();
    final production = _productionCtrl.text.trim();

    if (company.isEmpty) {
      _show("Company name is required");
      return;
    }

    setState(() => _saving = true);

    try {
      // ------------------------------------
      // 1. INSERT COMPANY
      // ------------------------------------
      final companyRes = await _client
          .from('companies')
          .insert({
            'name': company,
          })
          .select()
          .single();

      final companyId = companyRes['id'];

      // ------------------------------------
      // 2. INSERT CONTACT (optional)
      // ------------------------------------
      if (contactName.isNotEmpty) {
        await _client.from('contacts').insert({
          'company_id': companyId,
          'name': contactName,
          'email': email.isEmpty ? null : email,
          'phone': phone.isEmpty ? null : phone,
        });
      }

      // ------------------------------------
      // 3. INSERT PRODUCTION (optional)
      // ------------------------------------
      if (production.isNotEmpty) {
        await _client.from('productions').insert({
          'company_id': companyId,
          'name': production,
        });
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint("CREATE COMPANY ERROR: $e");

      _show("Failed to save company");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- HEADER
              const Text(
                "New company",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 16),

              // ---------------- COMPANY
              TextField(
                controller: _companyCtrl,
                decoration: const InputDecoration(
                  labelText: "Company name *",
                  prefixIcon: Icon(Icons.apartment),
                ),
              ),

              const SizedBox(height: 20),

              // ---------------- CONTACT
              const Text(
                "Contact",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 6),

              TextField(
                controller: _contactNameCtrl,
                decoration: const InputDecoration(
                  labelText: "Name",
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 6),

              TextField(
                controller: _contactEmailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email),
                ),
              ),

              const SizedBox(height: 6),

              TextField(
                controller: _contactPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Phone",
                  prefixIcon: Icon(Icons.phone),
                ),
              ),

              const SizedBox(height: 20),

              // ---------------- PRODUCTION
              const Text(
                "Production",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 6),

              TextField(
                controller: _productionCtrl,
                decoration: const InputDecoration(
                  labelText: "Production name",
                  prefixIcon: Icon(Icons.movie),
                ),
              ),

              const SizedBox(height: 24),

              // ---------------- BUTTONS
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text("Save"),
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