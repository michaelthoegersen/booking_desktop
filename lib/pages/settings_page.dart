import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/swe_settings.dart';
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
  late TextEditingController graphTenantIdCtrl;
  late TextEditingController graphClientIdCtrl;
  late TextEditingController graphClientSecretCtrl;
  late TextEditingController graphSenderEmailCtrl;

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
    graphTenantIdCtrl = TextEditingController(text: s.graphTenantId);
    graphClientIdCtrl = TextEditingController(text: s.graphClientId);
    graphClientSecretCtrl = TextEditingController(text: s.graphClientSecret);
    graphSenderEmailCtrl = TextEditingController(text: s.graphSenderEmail);

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
    graphTenantIdCtrl.dispose();
    graphClientIdCtrl.dispose();
    graphClientSecretCtrl.dispose();
    graphSenderEmailCtrl.dispose();

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

  Future<void> _openAddUserDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: "user");

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add user"),

          content: SizedBox(
            width: 400,
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

                TextField(
                  controller: roleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Role (admin / user)",
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
              onPressed: () async {

                await _createProfileUser(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  role: roleCtrl.text.trim(),
                );

                if (!mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("User created")),
                );
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // CALL EDGE FUNCTION
  // =====================================================

  Future<void> _createProfileUser({
    required String name,
    required String email,
    required String role,
  }) async {

    if (name.isEmpty || email.isEmpty) {
      debugPrint("❌ Name or email empty");
      return;
    }

    try {

      final supabase = Supabase.instance.client;

      final token =
          supabase.auth.currentSession?.accessToken;

      if (token == null) {
        debugPrint("❌ No auth token (not logged in)");
        return;
      }
final session = supabase.auth.currentSession;

debugPrint("SESSION: $session");
      final res = await supabase.functions.invoke(
        'create-user',
        body: {
          'name': name,
          'email': email,
          'role': role.isEmpty ? 'user' : role,
        },
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint("✅ Create user result: ${res.data}");

    } catch (e, st) {
      debugPrint("❌ Create user error:");
      debugPrint(e.toString());
      debugPrint(st.toString());
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
      graphTenantId: graphTenantIdCtrl.text.trim(),
      graphClientId: graphClientIdCtrl.text.trim(),
      graphClientSecret: graphClientSecretCtrl.text.trim(),
      graphSenderEmail: graphSenderEmailCtrl.text.trim(),
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

            // ---------------- GRAPH API ----------------

            Text(
              "Email (Microsoft Graph API)",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 4),

            Text(
              "Azure AD app registration with Mail.Send application permission. Register at portal.azure.com.",
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: graphTenantIdCtrl,
                    decoration: const InputDecoration(
                      labelText: "Tenant ID",
                      prefixIcon: Icon(Icons.corporate_fare),
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: graphClientIdCtrl,
                    decoration: const InputDecoration(
                      labelText: "Client ID",
                      prefixIcon: Icon(Icons.fingerprint),
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: graphClientSecretCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Client secret",
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: graphSenderEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Sender email address",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                ),
              ],
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
