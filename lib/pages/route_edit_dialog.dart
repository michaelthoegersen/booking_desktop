import 'package:flutter/material.dart';

import '../models/route_result.dart';
import '../services/routes_service.dart';

class RouteEditDialog extends StatefulWidget {
  final RouteResult? route;

  const RouteEditDialog({super.key, this.route});

  @override
  State<RouteEditDialog> createState() => _RouteEditDialogState();
}

class _RouteEditDialogState extends State<RouteEditDialog> {
  final _service = RoutesService();

  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _kmCtrl;
  late final TextEditingController _ferryCtrl;
  late final TextEditingController _tollCtrl;
  late final TextEditingController _extraCtrl;

  @override
  void initState() {
    super.initState();

    final r = widget.route;

    _fromCtrl = TextEditingController(text: r?.from ?? '');
    _toCtrl = TextEditingController(text: r?.to ?? '');
    _kmCtrl = TextEditingController(text: r?.km.toString() ?? '');
    _ferryCtrl = TextEditingController(text: r?.ferry.toString() ?? '0');
    _tollCtrl = TextEditingController(text: r?.toll.toString() ?? '0');
    _extraCtrl = TextEditingController(text: r?.extra ?? '');
  }

  Future<void> _save() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    if (from.isEmpty || to.isEmpty) return;

    final km = double.tryParse(_kmCtrl.text) ?? 0;
    final ferry = double.tryParse(_ferryCtrl.text) ?? 0;
    final toll = double.tryParse(_tollCtrl.text) ?? 0;
    final extra = _extraCtrl.text.trim();

    if (widget.route == null) {
      // CREATE
      await _service.createRoute(
        from: from,
        to: to,
        km: km,
        ferry: ferry,
        toll: toll,
        extra: extra,
      );
    } else {
      // UPDATE
      await _service.updateRoute(
        id: widget.route!.id,
        from: from,
        to: to,
        km: km,
        ferry: ferry,
        toll: toll,
        extra: extra,
      );
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.route == null ? 'New route' : 'Edit route'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _fromCtrl, decoration: const InputDecoration(labelText: 'From')),
              TextField(controller: _toCtrl, decoration: const InputDecoration(labelText: 'To')),
              TextField(controller: _kmCtrl, decoration: const InputDecoration(labelText: 'KM')),
              TextField(controller: _ferryCtrl, decoration: const InputDecoration(labelText: 'Ferry')),
              TextField(controller: _tollCtrl, decoration: const InputDecoration(labelText: 'Toll')),
              TextField(controller: _extraCtrl, decoration: const InputDecoration(labelText: 'Extra')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}