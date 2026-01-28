import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_clients.dart';

class EditCalendarJobDialog extends StatefulWidget {
  final String rowId;

  const EditCalendarJobDialog({
    super.key,
    required this.rowId,
  });

  @override
  State<EditCalendarJobDialog> createState() =>
      _EditCalendarJobDialogState();
}

class _EditCalendarJobDialogState
    extends State<EditCalendarJobDialog> {

  final sb = Supabase.instance.client;

  bool _loading = true;

  // Controllers
  final venueCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final timeCtrl = TextEditingController();
  final dDriveCtrl = TextEditingController();
  final getInCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  final ferryCtrl = TextEditingController();
  final attachmentCtrl = TextEditingController();
  final contactCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final statusCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    venueCtrl.dispose();
    addressCtrl.dispose();
    timeCtrl.dispose();
    dDriveCtrl.dispose();
    getInCtrl.dispose();
    commentCtrl.dispose();
    ferryCtrl.dispose();
    attachmentCtrl.dispose();
    contactCtrl.dispose();
    priceCtrl.dispose();
    statusCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------
  // Load row
  // ----------------------------------------
  Future<void> _load() async {
    final res = await sb
        .from('samletdata')
        .select()
        .eq('id', widget.rowId)
        .single();

    venueCtrl.text = res['venue'] ?? '';
    addressCtrl.text = res['adresse'] ?? '';
    timeCtrl.text = res['tid'] ?? '';
    dDriveCtrl.text = res['d_drive'] ?? '';
    getInCtrl.text = res['getin'] ?? '';
    commentCtrl.text = res['kommentarer'] ?? '';
    ferryCtrl.text = res['ferry'] ?? '';
    attachmentCtrl.text = res['vedlegg'] ?? '';
    contactCtrl.text = res['contact'] ?? '';
    priceCtrl.text = res['pris'] ?? '';
    statusCtrl.text = res['status'] ?? '';

    setState(() => _loading = false);
  }

  // ----------------------------------------
  // Save
  // ----------------------------------------
  Future<void> _save() async {
    await sb.from('samletdata').update({
      'venue': venueCtrl.text.trim(),
      'adresse': addressCtrl.text.trim(),
      'tid': timeCtrl.text.trim(),
      'd_drive': dDriveCtrl.text.trim(),
      'getin': getInCtrl.text.trim(),
      'kommentarer': commentCtrl.text.trim(),
      'ferry': ferryCtrl.text.trim(),
      'vedlegg': attachmentCtrl.text.trim(),
      'contact': contactCtrl.text.trim(),
      'pris': priceCtrl.text.trim(),
      'status': statusCtrl.text.trim(),
    }).eq('id', widget.rowId);

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  // ----------------------------------------
  // UI
  // ----------------------------------------
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit job"),

      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [

                    _field("Venue", venueCtrl),
                    _field("Address", addressCtrl),
                    _field("Time", timeCtrl),
                    _field("D. Drive", dDriveCtrl),
                    _field("Get-in", getInCtrl),
                    _field("Comments", commentCtrl),
                    _field("Ferry", ferryCtrl),
                    _field("Attachment", attachmentCtrl),
                    _field("Contact", contactCtrl),
                    _field("Price", priceCtrl),
                    _field("Status", statusCtrl),

                  ],
                ),
              ),
      ),

      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),

        FilledButton(
          onPressed: _save,
          child: const Text("Save"),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}