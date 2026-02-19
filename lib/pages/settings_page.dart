import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

            // ---------------- PRICES ----------------

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

            const Spacer(),

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
      onPressed: _openChangePasswordDialog, // ⭐ NY
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
      ),
    );
  }
}