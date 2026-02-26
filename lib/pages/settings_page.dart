import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/swe_settings.dart';
import '../services/km_se_updater.dart';
import '../state/settings_store.dart';
import '../pages/routes_admin_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController dayPriceCtrl;
  late TextEditingController extraKmCtrl;
  late TextEditingController trailerDayCtrl;
  late TextEditingController trailerKmCtrl;
  late TextEditingController dDriveDayCtrl;
  late TextEditingController flightTicketCtrl;
  late TextEditingController dropboxCtrl;
  late TextEditingController bankAccountCtrl;
  late TextEditingController tollKmRateCtrl;

  // --- Swedish pricing model ---
  late TextEditingController sweTimlonCtrl;
  late TextEditingController sweTimmarCtrl;
  late TextEditingController sweArbGAvgCtrl;
  late TextEditingController sweTraktamenteCtrl;
  late TextEditingController sweChaufforMarginalCtrl;

  late TextEditingController sweKopPrisCtrl;
  late TextEditingController sweAvskrivningArCtrl;
  late TextEditingController sweRantaCtrl;
  late TextEditingController sweForsakringCtrl;
  late TextEditingController sweSkattCtrl;
  late TextEditingController sweParkeringCtrl;
  late TextEditingController sweKordagarCtrl;
  late TextEditingController sweFordonMarginalCtrl;

  late TextEditingController sweDieselprisCtrl;
  late TextEditingController sweDieselforbrukningCtrl;
  late TextEditingController sweDackCtrl;
  late TextEditingController sweOljaCtrl;
  late TextEditingController sweVerkstadCtrl;
  late TextEditingController sweOvrigtCtrl;
  late TextEditingController sweKmMarginalCtrl;

  late TextEditingController sweDdTimlonCtrl;
  late TextEditingController sweDdTimmarCtrl;
  late TextEditingController sweDdArbGAvgCtrl;
  late TextEditingController sweDdTraktamenteCtrl;
  late TextEditingController sweDdResorCtrl;
  late TextEditingController sweDdHotellCtrl;
  late TextEditingController sweDdMarginalCtrl;
  late TextEditingController sweDdKmGransCtrl;

  late TextEditingController sweTrailerCtrl;
  late TextEditingController sweUtlandstraktCtrl;

  Future<void> _openChangePasswordDialog() async {

  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) {

      bool loading = false;

      return StatefulBuilder(
        builder: (context, setLocalState) {

          return AlertDialog(
            title: const Text("Change password"),

            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "New password",
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Confirm password",
                    ),
                  ),
                ],
              ),
            ),

            actions: [

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),

              FilledButton(
                onPressed: loading ? null : () async {

                  final p1 = passCtrl.text.trim();
                  final p2 = confirmCtrl.text.trim();

                  if (p1.isEmpty || p1 != p2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Passwords do not match"),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  setLocalState(() => loading = true);

                  try {

                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(password: p1),
                    );

                    if (!mounted) return;

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Password updated"),
                      ),
                    );

                  } catch (e) {

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }

                  setLocalState(() => loading = false);
                },
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Update"),
              ),
            ],
          );
        },
      );
    },
  );
}

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();

    final s = SettingsStore.current;

    dayPriceCtrl =
        TextEditingController(text: s.dayPrice.toStringAsFixed(0));
    extraKmCtrl =
        TextEditingController(text: s.extraKmPrice.toStringAsFixed(0));
    trailerDayCtrl =
        TextEditingController(text: s.trailerDayPrice.toStringAsFixed(0));
    trailerKmCtrl =
        TextEditingController(text: s.trailerKmPrice.toStringAsFixed(0));
    dDriveDayCtrl =
        TextEditingController(text: s.dDriveDayPrice.toStringAsFixed(0));
    flightTicketCtrl =
        TextEditingController(text: s.flightTicketPrice.toStringAsFixed(0));

    dropboxCtrl = TextEditingController(text: s.dropboxRootPath);
    bankAccountCtrl = TextEditingController(text: s.bankAccount);
    tollKmRateCtrl = TextEditingController(text: s.tollKmRate.toStringAsFixed(2));

    final swe = s.sweSettings;
    sweTimlonCtrl = TextEditingController(text: swe.timlon.toStringAsFixed(0));
    sweTimmarCtrl = TextEditingController(text: swe.timmarPerDag.toStringAsFixed(0));
    sweArbGAvgCtrl = TextEditingController(text: (swe.arbGAvg * 100).toStringAsFixed(2));
    sweTraktamenteCtrl = TextEditingController(text: swe.traktamente.toStringAsFixed(0));
    sweChaufforMarginalCtrl = TextEditingController(text: (swe.chaufforMarginal * 100).toStringAsFixed(0));

    sweKopPrisCtrl = TextEditingController(text: swe.kopPris.toStringAsFixed(0));
    sweAvskrivningArCtrl = TextEditingController(text: swe.avskrivningAr.toStringAsFixed(0));
    sweRantaCtrl = TextEditingController(text: (swe.rantaPerAr * 100).toStringAsFixed(1));
    sweForsakringCtrl = TextEditingController(text: swe.forsakringPerAr.toStringAsFixed(0));
    sweSkattCtrl = TextEditingController(text: swe.skattPerAr.toStringAsFixed(0));
    sweParkeringCtrl = TextEditingController(text: swe.parkeringPerAr.toStringAsFixed(0));
    sweKordagarCtrl = TextEditingController(text: swe.kordagarPerAr.toStringAsFixed(0));
    sweFordonMarginalCtrl = TextEditingController(text: (swe.fordonMarginal * 100).toStringAsFixed(0));

    sweDieselprisCtrl = TextEditingController(text: swe.dieselprisPerLiter.toStringAsFixed(2));
    sweDieselforbrukningCtrl = TextEditingController(text: swe.dieselforbrukningPerMil.toStringAsFixed(2));
    sweDackCtrl = TextEditingController(text: swe.dackKostnadPerMil.toStringAsFixed(2));
    sweOljaCtrl = TextEditingController(text: swe.oljaKostnadPerMil.toStringAsFixed(2));
    sweVerkstadCtrl = TextEditingController(text: swe.verkstadKostnadPerMil.toStringAsFixed(2));
    sweOvrigtCtrl = TextEditingController(text: swe.ovrigtKostnadPerMil.toStringAsFixed(2));
    sweKmMarginalCtrl = TextEditingController(text: (swe.kmMarginal * 100).toStringAsFixed(0));

    sweDdTimlonCtrl = TextEditingController(text: swe.ddTimlon.toStringAsFixed(0));
    sweDdTimmarCtrl = TextEditingController(text: swe.ddTimmarPerDag.toStringAsFixed(0));
    sweDdArbGAvgCtrl = TextEditingController(text: (swe.ddArbGAvg * 100).toStringAsFixed(2));
    sweDdTraktamenteCtrl = TextEditingController(text: swe.ddTraktamente.toStringAsFixed(0));
    sweDdResorCtrl = TextEditingController(text: swe.ddResor.toStringAsFixed(0));
    sweDdHotellCtrl = TextEditingController(text: swe.ddHotell.toStringAsFixed(0));
    sweDdMarginalCtrl = TextEditingController(text: (swe.ddMarginal * 100).toStringAsFixed(0));
    sweDdKmGransCtrl = TextEditingController(text: swe.ddKmGrans.toStringAsFixed(0));

    sweTrailerCtrl = TextEditingController(text: swe.trailerhyraPerDygn.toStringAsFixed(0));
    sweUtlandstraktCtrl = TextEditingController(text: swe.utlandstraktamente.toStringAsFixed(0));
  }

  @override
  void dispose() {
    dayPriceCtrl.dispose();
    extraKmCtrl.dispose();
    trailerDayCtrl.dispose();
    trailerKmCtrl.dispose();
    dDriveDayCtrl.dispose();
    flightTicketCtrl.dispose();
    dropboxCtrl.dispose();
    bankAccountCtrl.dispose();
    tollKmRateCtrl.dispose();

    sweTimlonCtrl.dispose();
    sweTimmarCtrl.dispose();
    sweArbGAvgCtrl.dispose();
    sweTraktamenteCtrl.dispose();
    sweChaufforMarginalCtrl.dispose();
    sweKopPrisCtrl.dispose();
    sweAvskrivningArCtrl.dispose();
    sweRantaCtrl.dispose();
    sweForsakringCtrl.dispose();
    sweSkattCtrl.dispose();
    sweParkeringCtrl.dispose();
    sweKordagarCtrl.dispose();
    sweFordonMarginalCtrl.dispose();
    sweDieselprisCtrl.dispose();
    sweDieselforbrukningCtrl.dispose();
    sweDackCtrl.dispose();
    sweOljaCtrl.dispose();
    sweVerkstadCtrl.dispose();
    sweOvrigtCtrl.dispose();
    sweKmMarginalCtrl.dispose();
    sweDdTimlonCtrl.dispose();
    sweDdTimmarCtrl.dispose();
    sweDdArbGAvgCtrl.dispose();
    sweDdTraktamenteCtrl.dispose();
    sweDdResorCtrl.dispose();
    sweDdHotellCtrl.dispose();
    sweDdMarginalCtrl.dispose();
    sweDdKmGransCtrl.dispose();
    sweTrailerCtrl.dispose();
    sweUtlandstraktCtrl.dispose();

    super.dispose();
  }

  // =====================================================
  // HELPERS
  // =====================================================

  double _parseDouble(String s, double fallback) {
    final clean = s.replaceAll(" ", "").replaceAll(",", ".");
    return double.tryParse(clean) ?? fallback;
  }

  // =====================================================
  // ADD USER DIALOG
  // =====================================================

  Future<List<Map<String, dynamic>>> _loadCompanies() async {
    try {
      final res = await Supabase.instance.client
          .from('companies')
          .select('id, name')
          .order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Load companies error: $e');
      return [];
    }
  }

  Future<void> _openAddUserDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedRole = 'user';
    String? selectedCompanyId;
    List<Map<String, dynamic>> companies = [];

    // Load companies for management role selection
    companies = await _loadCompanies();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add user"),

              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Name",
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: "Email",
                      ),
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: "Role",
                      ),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('admin')),
                        DropdownMenuItem(value: 'user', child: Text('user')),
                        DropdownMenuItem(
                            value: 'management', child: Text('management')),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          selectedRole = v ?? 'user';
                          if (selectedRole != 'management') {
                            selectedCompanyId = null;
                          }
                        });
                      },
                    ),

                    // Company dropdown — only shown for management role
                    if (selectedRole == 'management') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedCompanyId,
                        decoration: const InputDecoration(
                          labelText: "Company",
                          hintText: "Select company",
                        ),
                        items: companies
                            .map((c) => DropdownMenuItem<String>(
                                  value: c['id'] as String,
                                  child: Text(c['name'] as String? ?? ''),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedCompanyId = v),
                      ),
                    ],
                  ],
                ),
              ),

              actions: [

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),

                FilledButton(
                  onPressed: () async {

                    if (selectedRole == 'management' &&
                        selectedCompanyId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please select a company for management users"),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final tempPassword = await _createProfileUser(
                      name: nameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      role: selectedRole,
                      companyId: selectedRole == 'management'
                          ? selectedCompanyId
                          : null,
                    );

                    if (!mounted) return;

                    Navigator.pop(context);

                    if (tempPassword != null) {
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("User created"),
                          content: SizedBox(
                            width: 420,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Send these login details to ${nameCtrl.text.trim()}:"),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        "Email:     ${emailCtrl.text.trim()}",
                                        style: const TextStyle(fontFamily: 'monospace'),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        "Password:  $tempPassword",
                                        style: const TextStyle(fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  "The user should change their password after first login.",
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("OK"),
                            ),
                          ],
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("User created")),
                      );
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // CALL EDGE FUNCTION
  // =====================================================

  Future<String?> _createProfileUser({
    required String name,
    required String email,
    required String role,
    String? companyId,
  }) async {

    if (name.isEmpty || email.isEmpty) {
      debugPrint("❌ Name or email empty");
      return null;
    }

    try {

      final supabase = Supabase.instance.client;

      final body = {
        'name': name,
        'email': email,
        'role': role.isEmpty ? 'user' : role,
        if (companyId != null) 'company_id': companyId,
      };

      debugPrint("Creating user: $body");

      final res = await supabase.functions.invoke(
        'create-user',
        body: body,
      );

      debugPrint("✅ Create user result: ${res.data}");

      final data = res.data as Map<String, dynamic>?;
      return data?['temp_password'] as String?;

    } catch (e, st) {
      debugPrint("❌ Create user error:");
      debugPrint(e.toString());
      debugPrint(st.toString());
      return null;
    }
  }

  // =====================================================
  // DROPBOX
  // =====================================================

  Future<void> _chooseDropboxFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Select your Dropbox folder",
      lockParentWindow: true,
    );

    if (result == null) return;

    if (!await Directory(result).exists()) return;

    setState(() {
      dropboxCtrl.text = result;
    });
  }

  // =====================================================
  // =====================================================
  // POPULATE km_se
  // =====================================================

  Future<void> _runKmSeUpdater() async {
    final logs = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            // Start the updater the first time the dialog opens
            if (logs.isEmpty) {
              logs.add('Starter...');
              KmSeUpdater.updateAll(
                onProgress: (msg) => setS(() => logs.add(msg)),
                onError:    (msg) => setS(() => logs.add(msg)),
              ).then((_) {
                setS(() => logs.add('— Lukk vinduet når du er ferdig —'));
              });
            }

            return AlertDialog(
              title: const Text('Oppdater km_se for alle ruter'),
              content: SizedBox(
                width: 560,
                height: 360,
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    logs.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Lukk'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // SAVE SETTINGS
  // =====================================================

  Future<void> _save() async {
    final current = SettingsStore.current;

    SettingsStore.current = current.copyWith(
      dayPrice: _parseDouble(dayPriceCtrl.text, current.dayPrice),
      extraKmPrice: _parseDouble(extraKmCtrl.text, current.extraKmPrice),
      trailerDayPrice:
          _parseDouble(trailerDayCtrl.text, current.trailerDayPrice),
      trailerKmPrice:
          _parseDouble(trailerKmCtrl.text, current.trailerKmPrice),
      dDriveDayPrice:
          _parseDouble(dDriveDayCtrl.text, current.dDriveDayPrice),
      flightTicketPrice:
          _parseDouble(flightTicketCtrl.text, current.flightTicketPrice),
      dropboxRootPath: dropboxCtrl.text.trim(),
      bankAccount: bankAccountCtrl.text.trim(),
      tollKmRate: _parseDouble(tollKmRateCtrl.text, current.tollKmRate),
      sweSettings: SweSettings(
        timlon: _parseDouble(sweTimlonCtrl.text, current.sweSettings.timlon),
        timmarPerDag: _parseDouble(sweTimmarCtrl.text, current.sweSettings.timmarPerDag),
        arbGAvg: _parseDouble(sweArbGAvgCtrl.text, current.sweSettings.arbGAvg * 100) / 100,
        traktamente: _parseDouble(sweTraktamenteCtrl.text, current.sweSettings.traktamente),
        chaufforMarginal: _parseDouble(sweChaufforMarginalCtrl.text, current.sweSettings.chaufforMarginal * 100) / 100,
        kopPris: _parseDouble(sweKopPrisCtrl.text, current.sweSettings.kopPris),
        avskrivningAr: _parseDouble(sweAvskrivningArCtrl.text, current.sweSettings.avskrivningAr),
        rantaPerAr: _parseDouble(sweRantaCtrl.text, current.sweSettings.rantaPerAr * 100) / 100,
        forsakringPerAr: _parseDouble(sweForsakringCtrl.text, current.sweSettings.forsakringPerAr),
        skattPerAr: _parseDouble(sweSkattCtrl.text, current.sweSettings.skattPerAr),
        parkeringPerAr: _parseDouble(sweParkeringCtrl.text, current.sweSettings.parkeringPerAr),
        kordagarPerAr: _parseDouble(sweKordagarCtrl.text, current.sweSettings.kordagarPerAr),
        fordonMarginal: _parseDouble(sweFordonMarginalCtrl.text, current.sweSettings.fordonMarginal * 100) / 100,
        dieselprisPerLiter: _parseDouble(sweDieselprisCtrl.text, current.sweSettings.dieselprisPerLiter),
        dieselforbrukningPerMil: _parseDouble(sweDieselforbrukningCtrl.text, current.sweSettings.dieselforbrukningPerMil),
        dackKostnadPerMil: _parseDouble(sweDackCtrl.text, current.sweSettings.dackKostnadPerMil),
        oljaKostnadPerMil: _parseDouble(sweOljaCtrl.text, current.sweSettings.oljaKostnadPerMil),
        verkstadKostnadPerMil: _parseDouble(sweVerkstadCtrl.text, current.sweSettings.verkstadKostnadPerMil),
        ovrigtKostnadPerMil: _parseDouble(sweOvrigtCtrl.text, current.sweSettings.ovrigtKostnadPerMil),
        kmMarginal: _parseDouble(sweKmMarginalCtrl.text, current.sweSettings.kmMarginal * 100) / 100,
        ddTimlon: _parseDouble(sweDdTimlonCtrl.text, current.sweSettings.ddTimlon),
        ddTimmarPerDag: _parseDouble(sweDdTimmarCtrl.text, current.sweSettings.ddTimmarPerDag),
        ddArbGAvg: _parseDouble(sweDdArbGAvgCtrl.text, current.sweSettings.ddArbGAvg * 100) / 100,
        ddTraktamente: _parseDouble(sweDdTraktamenteCtrl.text, current.sweSettings.ddTraktamente),
        ddResor: _parseDouble(sweDdResorCtrl.text, current.sweSettings.ddResor),
        ddHotell: _parseDouble(sweDdHotellCtrl.text, current.sweSettings.ddHotell),
        ddMarginal: _parseDouble(sweDdMarginalCtrl.text, current.sweSettings.ddMarginal * 100) / 100,
        ddKmGrans: _parseDouble(sweDdKmGransCtrl.text, current.sweSettings.ddKmGrans),
        trailerhyraPerDygn: _parseDouble(sweTrailerCtrl.text, current.sweSettings.trailerhyraPerDygn),
        utlandstraktamente: _parseDouble(sweUtlandstraktCtrl.text, current.sweSettings.utlandstraktamente),
      ),
    );

    await SettingsStore.save();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Settings saved")),
    );

    setState(() {});
  }

  // =====================================================
  // FIELD
  // =====================================================

  Widget _field(
    String label,
    TextEditingController ctrl,
    String suffix,
  ) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
    );
  }

  Widget _sweField(String label, TextEditingController ctrl, String suffix,
      {double width = 200}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
        ),
      ),
    );
  }

  // =====================================================
  // SWEDISH SETTINGS SECTION
  // =====================================================

  Widget _buildSweSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final swe = SettingsStore.current.sweSettings;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          "Swedish pricing model (per leg)",
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          "Vehicle ${swe.fordonDagpris.toStringAsFixed(0)} + "
          "Driver ${swe.chaufforDagpris.toStringAsFixed(0)} + "
          "${swe.milpris.toStringAsFixed(0)} SEK/10km  •  "
          "DD ${swe.ddDagpris.toStringAsFixed(0)} when >${swe.ddKmGrans.toStringAsFixed(0)} km",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        children: [
          const SizedBox(height: 8),

          // --- DRIVER ---
          Text("Driver",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField("Hourly rate", sweTimlonCtrl, "SEK/h"),
            _sweField("Hours/day", sweTimmarCtrl, "h"),
            _sweField("Employer tax", sweArbGAvgCtrl, "%"),
            _sweField("Allowance", sweTraktamenteCtrl, "SEK/day"),
            _sweField("Margin", sweChaufforMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- VEHICLE ---
          Text("Vehicle",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField("Purchase price", sweKopPrisCtrl, "SEK", width: 220),
            _sweField("Depreciation", sweAvskrivningArCtrl, "years"),
            _sweField("Interest", sweRantaCtrl, "%/year"),
            _sweField("Insurance", sweForsakringCtrl, "SEK/year", width: 220),
            _sweField("Tax", sweSkattCtrl, "SEK/year", width: 220),
            _sweField("Parking", sweParkeringCtrl, "SEK/year", width: 220),
            _sweField("Driving days", sweKordagarCtrl, "days/year"),
            _sweField("Margin", sweFordonMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- KM PRICE ---
          Text("Km price (variable, per 10 km)",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField("Diesel price", sweDieselprisCtrl, "SEK/l"),
            _sweField("Consumption", sweDieselforbrukningCtrl, "l/10km"),
            _sweField("Tires", sweDackCtrl, "SEK/10km"),
            _sweField("Oil", sweOljaCtrl, "SEK/10km"),
            _sweField("Workshop", sweVerkstadCtrl, "SEK/10km"),
            _sweField("Other", sweOvrigtCtrl, "SEK/10km"),
            _sweField("Margin", sweKmMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- DD ---
          Text("Double driver (DD)",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField("Hourly rate", sweDdTimlonCtrl, "SEK/h"),
            _sweField("Hours/day", sweDdTimmarCtrl, "h"),
            _sweField("Employer tax", sweDdArbGAvgCtrl, "%"),
            _sweField("Allowance", sweDdTraktamenteCtrl, "SEK"),
            _sweField("Travel", sweDdResorCtrl, "SEK"),
            _sweField("Hotel", sweDdHotellCtrl, "SEK"),
            _sweField("Margin", sweDdMarginalCtrl, "%"),
            _sweField("Km threshold", sweDdKmGransCtrl, "km"),
          ]),
          const SizedBox(height: 16),

          // --- OTHER ---
          Text("Other",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField("Trailer hire", sweTrailerCtrl, "SEK/day", width: 220),
            _sweField("International allowance", sweUtlandstraktCtrl, "SEK/unit", width: 260),
          ]),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ---------------- TITLE ----------------

            Text(
              "Settings",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 14),

            // ---------------- DROPBOX ----------------

            Text(
              "Dropbox",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            Row(
              children: [

                Expanded(
                  child: TextField(
                    controller: dropboxCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Dropbox folder",
                      hintText: "Select Dropbox folder…",
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                FilledButton.icon(
                  onPressed: _chooseDropboxFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Choose"),
                )
              ],
            ),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- BANK ACCOUNT ----------------

            Text(
              "Invoice",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: 360,
              child: TextField(
                controller: bankAccountCtrl,
                decoration: const InputDecoration(
                  labelText: "Bank account number",
                  hintText: "e.g. 9710.05.12345",
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),
            ),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- SWEDISH PRICING MODEL ----------------

            _buildSweSection(context),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- PRICES (Norwegian model) ----------------

            Text(
              "Norsk prismodell",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [

                SizedBox(
                  width: 240,
                  child: _field("Day price", dayPriceCtrl, "NOK"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("Extra km price", extraKmCtrl, "NOK/km"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("Trailer day price", trailerDayCtrl, "NOK/day"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("Trailer km price", trailerKmCtrl, "NOK/km"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("D.Drive day price", dDriveDayCtrl, "NOK/day"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("Flight ticket price", flightTicketCtrl, "NOK"),
                ),

                SizedBox(
                  width: 240,
                  child: _field("Toll km-rate", tollKmRateCtrl, "NOK/km"),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ---------------- BUTTONS ----------------

            Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [

    FilledButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RoutesAdminPage(),
          ),
        );
      },
      icon: const Icon(Icons.route),
      label: const Text("Manage routes"),
    ),

    FilledButton.icon(
      onPressed: _runKmSeUpdater,
      icon: const Icon(Icons.map_outlined),
      label: const Text("Oppdater km Sverige"),
    ),

    FilledButton.icon(
      onPressed: _openAddUserDialog,
      icon: const Icon(Icons.person_add),
      label: const Text("Add user"),
    ),

    FilledButton.icon(
      onPressed: _openChangePasswordDialog,
      icon: const Icon(Icons.lock_reset),
      label: const Text("Change password"),
    ),

    FilledButton.icon(
      onPressed: _save,
      icon: const Icon(Icons.save),
      label: const Text("Save"),
    ),
  ],
),
          ],
        ),
        ),   // SingleChildScrollView
      ),
    );
  }
}
