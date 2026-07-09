import 'package:flutter/material.dart';

import '../../services/inventory_service.dart';
import 'inventory_common.dart';

/// Manage what's inside a container item (e.g. a Playbackrack).
/// Items placed inside inherit the container's location and move with it.
Future<void> showContainerContentsDialog(
  BuildContext context,
  InventoryService service,
  Map<String, dynamic> container,
) {
  return showDialog(
    context: context,
    builder: (_) =>
        _ContainerContentsDialog(service: service, container: container),
  );
}

class _ContainerContentsDialog extends StatefulWidget {
  final InventoryService service;
  final Map<String, dynamic> container;

  const _ContainerContentsDialog({required this.service, required this.container});

  @override
  State<_ContainerContentsDialog> createState() =>
      _ContainerContentsDialogState();
}

class _ContainerContentsDialogState extends State<_ContainerContentsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _candidates = [];
  Set<String> _inside = {};
  String _search = '';

  String get _containerId => widget.container['id'] as String;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.service.listItems();
      // Items that are themselves containers (have children) can't be nested,
      // to keep containment one level deep.
      final parentIds = <String>{
        for (final it in all)
          if (it['parent_id'] != null) it['parent_id'] as String
      };
      final candidates = all.where((it) {
        final id = it['id'] as String;
        if (id == _containerId) return false; // not itself
        if (parentIds.contains(id)) return false; // it's a container
        final parent = it['parent_id'] as String?;
        // Free items, or items already in THIS container.
        return parent == null || parent == _containerId;
      }).toList();
      final inside = <String>{
        for (final it in all)
          if (it['parent_id'] == _containerId) it['id'] as String
      };
      if (mounted) {
        setState(() {
          _candidates = candidates;
          _inside = inside;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String itemId, bool on) async {
    setState(() {
      if (on) {
        _inside.add(itemId);
      } else {
        _inside.remove(itemId);
      }
    });
    try {
      await widget.service.setParent(
        itemId: itemId,
        parentId: on ? _containerId : null,
        locType: widget.container['location_type'] as String?,
        locRef: widget.container['location_ref'] as String?,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (on) {
          _inside.remove(itemId);
        } else {
          _inside.add(itemId);
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates.where((it) {
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
    final name = widget.container['name'] as String? ?? '';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Innhold — $name'),
          const SizedBox(height: 2),
          Text('Utstyr her flyttes inn/ut sammen med enheten',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _candidates.isEmpty
                ? Center(
                    child: Text(
                      'Ingen ledige varer å legge i enheten.\n'
                      'Legg til utstyr i Lager først.',
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
                                  final on = _inside.contains(itemId);
                                  final cat = (it['category'] as String?)?.trim();
                                  return CheckboxListTile(
                                    dense: true,
                                    value: on,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(it['name'] as String? ?? ''),
                                    subtitle: Text([
                                      if (cat != null && cat.isNotEmpty) cat,
                                      fmtQty(it),
                                    ].join('  ·  ')),
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
            Text('${_inside.length} i enheten',
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
