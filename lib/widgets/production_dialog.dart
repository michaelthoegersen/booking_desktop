import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductionDialog extends StatefulWidget {
  /// Pass [companyId] for create mode, [existing] for edit mode.
  final String companyId;
  final Map<String, dynamic>? existing;

  const ProductionDialog({
    super.key,
    required this.companyId,
    this.existing,
  });

  @override
  State<ProductionDialog> createState() => _ProductionDialogState();
}

class _ProductionDialogState extends State<ProductionDialog> {
  final SupabaseClient _client = Supabase.instance.client;

  late final TextEditingController _nameCtrl;
  late bool _separateInvoice;
  late final TextEditingController _invoiceNameCtrl;
  late final TextEditingController _invoiceOrgNrCtrl;
  late final TextEditingController _invoiceAddressCtrl;
  late final TextEditingController _invoicePostalCodeCtrl;
  late final TextEditingController _invoiceCityCtrl;
  late final TextEditingController _invoiceCountryCtrl;
  late final TextEditingController _invoiceEmailCtrl;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?['name'] ?? '');
    _separateInvoice = p?['separate_invoice_recipient'] ?? false;
    _invoiceNameCtrl = TextEditingController(text: p?['invoice_name'] ?? '');
    _invoiceOrgNrCtrl = TextEditingController(text: p?['invoice_org_nr'] ?? '');
    _invoiceAddressCtrl = TextEditingController(text: p?['invoice_address'] ?? '');
    _invoicePostalCodeCtrl = TextEditingController(text: p?['invoice_postal_code'] ?? '');
    _invoiceCityCtrl = TextEditingController(text: p?['invoice_city'] ?? '');
    _invoiceCountryCtrl = TextEditingController(text: p?['invoice_country'] ?? '');
    _invoiceEmailCtrl = TextEditingController(text: p?['invoice_email'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _invoiceNameCtrl.dispose();
    _invoiceOrgNrCtrl.dispose();
    _invoiceAddressCtrl.dispose();
    _invoicePostalCodeCtrl.dispose();
    _invoiceCityCtrl.dispose();
    _invoiceCountryCtrl.dispose();
    _invoiceEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Production name is required")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final invoiceName = _invoiceNameCtrl.text.trim();
      final invoiceOrgNr = _invoiceOrgNrCtrl.text.trim();
      final invoiceAddress = _invoiceAddressCtrl.text.trim();
      final invoicePostalCode = _invoicePostalCodeCtrl.text.trim();
      final invoiceCity = _invoiceCityCtrl.text.trim();
      final invoiceCountry = _invoiceCountryCtrl.text.trim();
      final invoiceEmail = _invoiceEmailCtrl.text.trim();

      final data = {
        'name': name,
        'company_id': widget.companyId,
        'separate_invoice_recipient': _separateInvoice,
        'invoice_name': _separateInvoice && invoiceName.isNotEmpty ? invoiceName : null,
        'invoice_org_nr': _separateInvoice && invoiceOrgNr.isNotEmpty ? invoiceOrgNr : null,
        'invoice_address': _separateInvoice && invoiceAddress.isNotEmpty ? invoiceAddress : null,
        'invoice_postal_code': _separateInvoice && invoicePostalCode.isNotEmpty ? invoicePostalCode : null,
        'invoice_city': _separateInvoice && invoiceCity.isNotEmpty ? invoiceCity : null,
        'invoice_country': _separateInvoice && invoiceCountry.isNotEmpty ? invoiceCountry : null,
        'invoice_email': _separateInvoice && invoiceEmail.isNotEmpty ? invoiceEmail : null,
      };

      if (_isEdit) {
        await _client
            .from('productions')
            .update(data)
            .eq('id', widget.existing!['id']);
      } else {
        await _client.from('productions').insert(data);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint("PRODUCTION SAVE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save production")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? "Edit production" : "New production",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 16),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Production name
                      TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: "Production name *",
                          prefixIcon: Icon(Icons.movie),
                        ),
                      ),

                      const Divider(height: 32),

                      // Separate invoice recipient toggle
                      CheckboxListTile(
                        value: _separateInvoice,
                        onChanged: (v) =>
                            setState(() => _separateInvoice = v ?? false),
                        title: const Text("Separate invoice recipient"),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _separateInvoice
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _invoiceNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Invoice recipient name",
                                      prefixIcon: Icon(Icons.business),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceOrgNrCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Org.nr",
                                      prefixIcon: Icon(Icons.numbers),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceAddressCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Address",
                                      prefixIcon: Icon(Icons.location_on),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 120,
                                        child: TextField(
                                          controller: _invoicePostalCodeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: "Postal code",
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _invoiceCityCtrl,
                                          decoration: const InputDecoration(
                                            labelText: "City",
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceCountryCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Country",
                                      prefixIcon: Icon(Icons.flag),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceEmailCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Invoice email",
                                      prefixIcon: Icon(Icons.email),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
