import 'package:flutter/material.dart';

import '../../services/inventory_service.dart';
import '../../services/show_equipment_service.dart';
import 'inventory_common.dart';

/// Pick which equipment (from mgmt Lager) is tied to a fixed show.
Future<void> showFixedShowEquipmentDialog(
  BuildContext context, {
  required String showTypeId,
  required String showName,
}) {
  return _open(
    context,
    title: 'Utstyr — $showName',
    subtitle: 'Utstyr som alltid brukes på dette showet',
    table: ShowEquipmentService.showTypeTable,
    column: ShowEquipmentService.showTypeColumn,
    id: showTypeId,
  );
}

/// Pick which equipment is tied to one show on a specific gig (incl. custom).
Future<void> showGigShowEquipmentDialog(
  BuildContext context, {
  required String gigShowId,
  required String showName,
}) {
  return _open(
    context,
    title: 'Utstyr — $showName',
    subtitle: 'Utstyr til dette showet på giggen',
    table: ShowEquipmentService.gigShowTable,
    column: ShowEquipmentService.gigShowColumn,
    id: gigShowId,
  );
}

Future<void> _open(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String table,
  required String column,
  required String id,
}) {
  return showDialog(
    context: context,
    builder: (_) => _ShowEquipmentDialog(
      title: title,
      subtitle: subtitle,
      table: table,
      column: column,
      id: id,
    ),
  );
}

class _ShowEquipmentDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String table;
  final String column;
  final String id;

  const _ShowEquipmentDialog({
    required this.title,
    required this.subtitle,
    required this.table,
    required this.column,
    required this.id,
  });

  @override
  State<_ShowEquipmentDialog> createState() => _ShowEquipmentDialogState();
}

class _ShowEquipmentDialogState extends State<_ShowEquipmentDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  Set<String> _linked = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await mgmtInventoryService.listItems();
      final linked = await ShowEquipmentService.linkedItemIds(
        table: widget.table,
        column: widget.column,
        id: widget.id,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _linked = linked;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String itemId, bool on) async {
    // Optimistic UI
    setState(() {
      if (on) {
        _linked.add(itemId);
      } else {
        _linked.remove(itemId);
      }
    });
    try {
      if (on) {
        await ShowEquipmentService.addLink(
            table: widget.table, column: widget.column, id: widget.id, itemId: itemId);
      } else {
        await ShowEquipmentService.removeLink(
            table: widget.table, column: widget.column, id: widget.id, itemId: itemId);
      }
    } catch (e) {
      if (!mounted) return;
      // Revert on failure
      setState(() {
        if (on) {
          _linked.remove(itemId);
        } else {
          _linked.add(itemId);
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((it) {
      final hay = [it['name'], it['category'], it['ref_number']]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          const SizedBox(height: 2),
          Text(widget.subtitle,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(
                    child: Text(
                      'Ingen utstyr i Lager ennå.\nLegg til utstyr i Lager først.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : Column(
                    children: [
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: kCapFirst,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Søk i utstyr…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text('Ingen treff.',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant)))
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final it = items[i];
                                  final itemId = it['id'] as String;
                                  final on = _linked.contains(itemId);
                                  final cat =
                                      (it['category'] as String?)?.trim();
                                  return CheckboxListTile(
                                    dense: true,
                                    value: on,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(it['name'] as String? ?? ''),
                                    subtitle: Text(
                                      [
                                        if (cat != null && cat.isNotEmpty) cat,
                                        fmtQty(it),
                                        locDisplay(it),
                                      ].join('  ·  '),
                                    ),
                                    onChanged: (v) => _toggle(itemId, v ?? false),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        Row(
          children: [
            Text('${_linked.length} valgt',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ferdig'),
            ),
          ],
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    );
  }
}
