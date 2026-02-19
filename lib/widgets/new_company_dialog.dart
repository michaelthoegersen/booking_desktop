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
  final _orgNrCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  bool _separateInvoice = false;
  final _invoiceNameCtrl = TextEditingController();
  final _invoiceOrgNrCtrl = TextEditingController();
  final _invoiceAddressCtrl = TextEditingController();
  final _invoicePostalCodeCtrl = TextEditingController();
  final _invoiceCityCtrl = TextEditingController();
  final _invoiceCountryCtrl = TextEditingController();
  final _invoiceEmailCtrl = TextEditingController();

  final _contactNameCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  final _productionCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _companyCtrl.dispose();
    _orgNrCtrl.dispose();
    _addressCtrl.dispose();
    _postalCodeCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _invoiceNameCtrl.dispose();
    _invoiceOrgNrCtrl.dispose();
    _invoiceAddressCtrl.dispose();
    _invoicePostalCodeCtrl.dispose();
    _invoiceCityCtrl.dispose();
    _invoiceCountryCtrl.dispose();
    _invoiceEmailCtrl.dispose();
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
    final orgNr = _orgNrCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final postalCode = _postalCodeCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final invoiceName = _invoiceNameCtrl.text.trim();
    final invoiceOrgNr = _invoiceOrgNrCtrl.text.trim();
    final invoiceAddress = _invoiceAddressCtrl.text.trim();
    final invoicePostalCode = _invoicePostalCodeCtrl.text.trim();
    final invoiceCity = _invoiceCityCtrl.text.trim();
    final invoiceCountry = _invoiceCountryCtrl.text.trim();
    final invoiceEmail = _invoiceEmailCtrl.text.trim();
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
            'org_nr': orgNr.isEmpty ? null : orgNr,
            'address': address.isEmpty ? null : address,
            'postal_code': postalCode.isEmpty ? null : postalCode,
            'city': city.isEmpty ? null : city,
            'country': country.isEmpty ? null : country,
            'separate_invoice_recipient': _separateInvoice,
            if (_separateInvoice) ...{
              'invoice_name': invoiceName.isEmpty ? null : invoiceName,
              'invoice_org_nr': invoiceOrgNr.isEmpty ? null : invoiceOrgNr,
              'invoice_address': invoiceAddress.isEmpty ? null : invoiceAddress,
              'invoice_postal_code': invoicePostalCode.isEmpty ? null : invoicePostalCode,
              'invoice_city': invoiceCity.isEmpty ? null : invoiceCity,
              'invoice_country': invoiceCountry.isEmpty ? null : invoiceCountry,
              'invoice_email': invoiceEmail.isEmpty ? null : invoiceEmail,
            },
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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: 520,
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

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------- COMPANY NAME
                      TextField(
                        controller: _companyCtrl,
                        decoration: const InputDecoration(
                          labelText: "Company name *",
                          prefixIcon: Icon(Icons.apartment),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- ORG NR
                      TextField(
                        controller: _orgNrCtrl,
                        decoration: const InputDecoration(
                          labelText: "Org.nr",
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- ADDRESS
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: "Address",
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- POSTAL + CITY
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _postalCodeCtrl,
                              decoration: const InputDecoration(
                                labelText: "Postal code",
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cityCtrl,
                              decoration: const InputDecoration(
                                labelText: "City",
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // ---------------- COUNTRY
                      TextField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(
                          labelText: "Country",
                          prefixIcon: Icon(Icons.flag),
                        ),
                      ),

                      const Divider(height: 32),

                      // ---------------- SEPARATE INVOICE RECIPIENT
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
                                      labelText: "Invoice org.nr",
                                      prefixIcon: Icon(Icons.numbers),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceAddressCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Invoice address",
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
                                      labelText: "Invoice country",
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

                      const Divider(height: 32),

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
                    ],
                  ),
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

// ==================================================
// EDIT COMPANY DIALOG
// ==================================================
class EditCompanyDialog extends StatefulWidget {
  final Map<String, dynamic> company;

  const EditCompanyDialog({super.key, required this.company});

  @override
  State<EditCompanyDialog> createState() => _EditCompanyDialogState();
}

class _EditCompanyDialogState extends State<EditCompanyDialog> {
  final SupabaseClient _client = Supabase.instance.client;

  late final TextEditingController _companyCtrl;
  late final TextEditingController _orgNrCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _countryCtrl;

  late bool _separateInvoice;
  late final TextEditingController _invoiceNameCtrl;
  late final TextEditingController _invoiceOrgNrCtrl;
  late final TextEditingController _invoiceAddressCtrl;
  late final TextEditingController _invoicePostalCodeCtrl;
  late final TextEditingController _invoiceCityCtrl;
  late final TextEditingController _invoiceCountryCtrl;
  late final TextEditingController _invoiceEmailCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.company;
    _companyCtrl = TextEditingController(text: c['name'] ?? '');
    _orgNrCtrl = TextEditingController(text: c['org_nr'] ?? '');
    _addressCtrl = TextEditingController(text: c['address'] ?? '');
    _postalCodeCtrl = TextEditingController(text: c['postal_code'] ?? '');
    _cityCtrl = TextEditingController(text: c['city'] ?? '');
    _countryCtrl = TextEditingController(text: c['country'] ?? '');
    _separateInvoice = c['separate_invoice_recipient'] ?? false;
    _invoiceNameCtrl = TextEditingController(text: c['invoice_name'] ?? '');
    _invoiceOrgNrCtrl = TextEditingController(text: c['invoice_org_nr'] ?? '');
    _invoiceAddressCtrl = TextEditingController(text: c['invoice_address'] ?? '');
    _invoicePostalCodeCtrl = TextEditingController(text: c['invoice_postal_code'] ?? '');
    _invoiceCityCtrl = TextEditingController(text: c['invoice_city'] ?? '');
    _invoiceCountryCtrl = TextEditingController(text: c['invoice_country'] ?? '');
    _invoiceEmailCtrl = TextEditingController(text: c['invoice_email'] ?? '');
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _orgNrCtrl.dispose();
    _addressCtrl.dispose();
    _postalCodeCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
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
    final company = _companyCtrl.text.trim();
    if (company.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Company name is required")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final orgNr = _orgNrCtrl.text.trim();
      final address = _addressCtrl.text.trim();
      final postalCode = _postalCodeCtrl.text.trim();
      final city = _cityCtrl.text.trim();
      final country = _countryCtrl.text.trim();
      final invoiceName = _invoiceNameCtrl.text.trim();
      final invoiceOrgNr = _invoiceOrgNrCtrl.text.trim();
      final invoiceAddress = _invoiceAddressCtrl.text.trim();
      final invoicePostalCode = _invoicePostalCodeCtrl.text.trim();
      final invoiceCity = _invoiceCityCtrl.text.trim();
      final invoiceCountry = _invoiceCountryCtrl.text.trim();
      final invoiceEmail = _invoiceEmailCtrl.text.trim();

      await _client.from('companies').update({
        'name': company,
        'org_nr': orgNr.isEmpty ? null : orgNr,
        'address': address.isEmpty ? null : address,
        'postal_code': postalCode.isEmpty ? null : postalCode,
        'city': city.isEmpty ? null : city,
        'country': country.isEmpty ? null : country,
        'separate_invoice_recipient': _separateInvoice,
        'invoice_name': _separateInvoice && invoiceName.isNotEmpty ? invoiceName : null,
        'invoice_org_nr': _separateInvoice && invoiceOrgNr.isNotEmpty ? invoiceOrgNr : null,
        'invoice_address': _separateInvoice && invoiceAddress.isNotEmpty ? invoiceAddress : null,
        'invoice_postal_code': _separateInvoice && invoicePostalCode.isNotEmpty ? invoicePostalCode : null,
        'invoice_city': _separateInvoice && invoiceCity.isNotEmpty ? invoiceCity : null,
        'invoice_country': _separateInvoice && invoiceCountry.isNotEmpty ? invoiceCountry : null,
        'invoice_email': _separateInvoice && invoiceEmail.isNotEmpty ? invoiceEmail : null,
      }).eq('id', widget.company['id']);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint("EDIT COMPANY ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save company")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- HEADER
              const Text(
                "Edit company",
                style: TextStyle(
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
                      // ---------------- COMPANY NAME
                      TextField(
                        controller: _companyCtrl,
                        decoration: const InputDecoration(
                          labelText: "Company name *",
                          prefixIcon: Icon(Icons.apartment),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- ORG NR
                      TextField(
                        controller: _orgNrCtrl,
                        decoration: const InputDecoration(
                          labelText: "Org.nr",
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- ADDRESS
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: "Address",
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------------- POSTAL + CITY
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _postalCodeCtrl,
                              decoration: const InputDecoration(
                                labelText: "Postal code",
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cityCtrl,
                              decoration: const InputDecoration(
                                labelText: "City",
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // ---------------- COUNTRY
                      TextField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(
                          labelText: "Country",
                          prefixIcon: Icon(Icons.flag),
                        ),
                      ),

                      const Divider(height: 32),

                      // ---------------- SEPARATE INVOICE RECIPIENT
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
                                      labelText: "Invoice org.nr",
                                      prefixIcon: Icon(Icons.numbers),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _invoiceAddressCtrl,
                                    decoration: const InputDecoration(
                                      labelText: "Invoice address",
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
                                      labelText: "Invoice country",
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
