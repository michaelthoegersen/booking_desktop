import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/route_result.dart';
import '../services/routes_service.dart';

class RouteEditDialog extends StatefulWidget {
  final RouteResult? route;
  final RoutesService service;

  const RouteEditDialog({
    super.key,
    required this.service,
    this.route,
  });

  @override
  State<RouteEditDialog> createState() => _RouteEditDialogState();
}

class _RouteEditDialogState extends State<RouteEditDialog> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  late TextEditingController _kmCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _fromCtrl = TextEditingController(text: widget.route?.from ?? '');
    _toCtrl = TextEditingController(text: widget.route?.to ?? '');
    _kmCtrl = TextEditingController(
      text: widget.route?.km.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // SAVE
  // ------------------------------------------------------------
  Future<void> _save() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    final km = double.tryParse(_kmCtrl.text);

    if (from.isEmpty || to.isEmpty || km == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid input')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      if (widget.route == null) {
        // CREATE
        await widget.service.createRoute(
          from: from,
          to: to,
          km: km,
        );
      } else {
        // UPDATE
        await widget.service.updateRoute(
          id: widget.route!.id,
          from: from,
          to: to,
          km: km,
        );
      }

      if (!mounted) return;

      context.pop(true);
    } catch (e, st) {
      debugPrint('SAVE ERROR: $e');
      debugPrint(st.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.route == null ? 'New route' : 'Edit route'),

      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(labelText: 'From'),
            ),

            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(labelText: 'To'),
            ),

            TextField(
              controller: _kmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Distance (km)'),
            ),
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving ? null : () => context.pop(false),
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}