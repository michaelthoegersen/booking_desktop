import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  // ✅ NEW
  late TextEditingController dropboxCtrl;

  @override
  void initState() {
    super.initState();
    final s = SettingsStore.current;

    dayPriceCtrl = TextEditingController(text: s.dayPrice.toStringAsFixed(0));
    extraKmCtrl = TextEditingController(text: s.extraKmPrice.toStringAsFixed(0));
    trailerDayCtrl = TextEditingController(text: s.trailerDayPrice.toStringAsFixed(0));
    trailerKmCtrl = TextEditingController(text: s.trailerKmPrice.toStringAsFixed(0));
    dDriveDayCtrl = TextEditingController(text: s.dDriveDayPrice.toStringAsFixed(0));
    flightTicketCtrl = TextEditingController(text: s.flightTicketPrice.toStringAsFixed(0));

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

  double _parseDouble(String s, double fallback) {
    final clean = s.replaceAll(" ", "").replaceAll(",", ".");
    return double.tryParse(clean) ?? fallback;
  }

  Future<void> _chooseDropboxFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Select your Dropbox folder",
      lockParentWindow: true,
    );

    if (result == null) return;

    // optional: ensure path exists
    if (!await Directory(result).exists()) return;

    setState(() {
      dropboxCtrl.text = result;
    });
  }

  Future<void> _save() async {
    final current = SettingsStore.current;

    SettingsStore.current = current.copyWith(
      dayPrice: _parseDouble(dayPriceCtrl.text, current.dayPrice),
      extraKmPrice: _parseDouble(extraKmCtrl.text, current.extraKmPrice),
      trailerDayPrice: _parseDouble(trailerDayCtrl.text, current.trailerDayPrice),
      trailerKmPrice: _parseDouble(trailerKmCtrl.text, current.trailerKmPrice),
      dDriveDayPrice: _parseDouble(dDriveDayCtrl.text, current.dDriveDayPrice),
      flightTicketPrice: _parseDouble(flightTicketCtrl.text, current.flightTicketPrice),

      // ✅ NEW:
      dropboxRootPath: dropboxCtrl.text.trim(),
    );

    await SettingsStore.save(); // ✅ persist

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings saved")));
    setState(() {});
  }

  Widget _field(String label, TextEditingController ctrl, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
    );
  }

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
            Text(
              "Settings",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),

            // ✅ Dropbox section
            Text(
              "Dropbox",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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

            // prices
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(width: 240, child: _field("Day price", dayPriceCtrl, "NOK")),
                SizedBox(width: 240, child: _field("Extra km price", extraKmCtrl, "NOK/km")),
                SizedBox(width: 240, child: _field("Trailer day price", trailerDayCtrl, "NOK/day")),
                SizedBox(width: 240, child: _field("Trailer km price", trailerKmCtrl, "NOK/km")),
                SizedBox(width: 240, child: _field("D.Drive day price", dDriveDayCtrl, "NOK/day")),
                SizedBox(width: 240, child: _field("Flight ticket price", flightTicketCtrl, "NOK")),
              ],
            ),

            const Spacer(),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text("Save"),
              ),
            )
          ],
        ),
      ),
    );
  }
}