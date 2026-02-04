import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/settings_store.dart';

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
                  onPressed: _openAddUserDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text("Add user"),
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