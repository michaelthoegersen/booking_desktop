import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Map<String, num> _linkedQty = {};
  Map<String, String?> _linkedNote = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await mgmtInventoryService.listItems();
      final rows = await ShowEquipmentService.linkedRows(
        table: widget.table,
        column: widget.column,
        id: widget.id,
      );
      final qty = <String, num>{};
      final note = <String, String?>{};
      for (final r in rows) {
        final itemId = r['item_id'] as String;
        qty[itemId] = (r['quantity'] as num?) ?? 1;
        note[itemId] = r['note'] as String?;
      }
      if (mounted) {
        setState(() {
          _items = items;
          _linkedQty = qty;
          _linkedNote = note;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String itemId, bool on) async {
    final prev = _linkedQty[itemId];
    setState(() {
      if (on) {
        _linkedQty[itemId] = 1;
      } else {
        _linkedQty.remove(itemId);
        _linkedNote.remove(itemId);
      }
    });
    try {
      if (on) {
        await ShowEquipmentService.addLink(
            table: widget.table,
            column: widget.column,
            id: widget.id,
            itemId: itemId,
            quantity: 1);
      } else {
        await ShowEquipmentService.removeLink(
            table: widget.table, column: widget.column, id: widget.id, itemId: itemId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (prev == null) {
          _linkedQty.remove(itemId);
        } else {
          _linkedQty[itemId] = prev;
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
    }
  }

  Future<void> _setQty(String itemId, num qty) async {
    if (qty < 1) qty = 1;
    final prev = _linkedQty[itemId] ?? 1;
    setState(() => _linkedQty[itemId] = qty);
    try {
      await ShowEquipmentService.addLink(
          table: widget.table,
          column: widget.column,
          id: widget.id,
          itemId: itemId,
          quantity: qty);
    } catch (e) {
      if (!mounted) return;
      setState(() => _linkedQty[itemId] = prev);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
    }
  }

  Future<void> _promptNote(String itemId, String itemName) async {
    final ctrl = TextEditingController(text: _linkedNote[itemId] ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Kommentar — $itemName'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: kCapFirst,
          decoration: const InputDecoration(
            hintText: 'F.eks. hvilke trommer vi skal ha med',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Avbryt')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Lagre')),
        ],
      ),
    );
    if (res == null) return; // cancelled
    final note = res.trim().isEmpty ? null : res.trim();
    final prev = _linkedNote[itemId];
    setState(() => _linkedNote[itemId] = note);
    try {
      await ShowEquipmentService.setNote(
        table: widget.table,
        column: widget.column,
        id: widget.id,
        itemId: itemId,
        note: note,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _linkedNote[itemId] = prev);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
    }
  }

  /// Flattened display list: top-level items (containers shown as a unit)
  /// followed by their contents, so each item inside a case can be ticked
  /// individually (for taking something out loose).
  List<({Map<String, dynamic> item, bool isChild, bool isContainer})>
      get _entries {
    final q = _search.trim().toLowerCase();
    bool matches(Map<String, dynamic> it) {
      if (q.isEmpty) return true;
      final hay = [it['name'], it['category'], it['ref_number']]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return hay.contains(q);
    }

    final childrenByParent = <String, List<Map<String, dynamic>>>{};
    for (final it in _items) {
      final p = it['parent_id'] as String?;
      if (p != null) childrenByParent.putIfAbsent(p, () => []).add(it);
    }

    final entries =
        <({Map<String, dynamic> item, bool isChild, bool isContainer})>[];
    for (final it in _items) {
      if (it['parent_id'] != null) continue; // children render under parent
      final id = it['id'] as String;
      final children = childrenByParent[id] ?? const <Map<String, dynamic>>[];
      final selfMatch = matches(it);
      final shownChildren =
          selfMatch ? children : children.where(matches).toList();
      if (!selfMatch && shownChildren.isEmpty) continue;
      entries
          .add((item: it, isChild: false, isContainer: children.isNotEmpty));
      for (final c in shownChildren) {
        entries.add((item: c, isChild: true, isContainer: false));
      }
    }
    return entries;
  }

  Widget _buildItemRow(BuildContext context, Map<String, dynamic> it,
      {required bool isChild, required bool isContainer}) {
    final cs = Theme.of(context).colorScheme;
    final itemId = it['id'] as String;
    final on = _linkedQty.containsKey(itemId);
    final qty = _linkedQty[itemId] ?? 1;
    final note = _linkedNote[itemId];
    return Padding(
      padding: EdgeInsets.only(left: isChild ? 24 : 0, top: 2, bottom: 2),
      child: Row(
        children: [
          if (isChild)
            Icon(Icons.subdirectory_arrow_right,
                size: 16, color: cs.onSurfaceVariant),
          Checkbox(
            value: on,
            onChanged: (v) => _toggle(itemId, v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isContainer) ...[
                      Icon(Icons.inventory_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(it['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (isContainer)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('Enhet',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary)),
                      ),
                  ],
                ),
                Text('på lager: ${fmtQty(it)}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                if (on && (note?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note!,
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: cs.primary)),
                  ),
              ],
            ),
          ),
          if (on)
            IconButton(
              icon: Icon(
                (note?.isNotEmpty ?? false)
                    ? Icons.chat_bubble
                    : Icons.chat_bubble_outline,
                size: 18,
              ),
              tooltip: 'Kommentar',
              visualDensity: VisualDensity.compact,
              onPressed: () => _promptNote(itemId, it['name'] as String? ?? ''),
            ),
          if (on)
            _QtyStepper(
              value: qty,
              max: (it['quantity'] as num?) ?? 1,
              onChanged: (q) => _setQty(itemId, q),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;

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
                        child: entries.isEmpty
                            ? Center(
                                child: Text('Ingen treff.',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant)))
                            : ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e = entries[i];
                                  return _buildItemRow(
                                    context,
                                    e.item,
                                    isChild: e.isChild,
                                    isContainer: e.isContainer,
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
            Text('${_linkedQty.length} valgt',
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

/// Compact −/N/+ quantity control, capped at [max] (stock on hand).
/// Tap the number to type a value directly.
class _QtyStepper extends StatelessWidget {
  final num value;
  final num? max;
  final ValueChanged<num> onChanged;

  const _QtyStepper({
    required this.value,
    this.max,
    required this.onChanged,
  });

  static String _n(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : '$v';

  num _clamp(num v) {
    if (v < 1) return 1;
    if (max != null && v > max!) return max!;
    return v;
  }

  Future<void> _promptValue(BuildContext context) async {
    final ctrl = TextEditingController(text: _n(value));
    final res = await showDialog<num>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Antall som trengs'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: max != null ? 'På lager: ${_n(max!)}' : null,
          ),
          onSubmitted: (_) =>
              Navigator.pop(context, num.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Avbryt')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, num.tryParse(ctrl.text.trim())),
              child: const Text('OK')),
        ],
      ),
    );
    if (res != null) onChanged(_clamp(res));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final atMax = max != null && value >= max!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
          ),
          InkWell(
            onTap: () => _promptValue(context),
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Text(
                max != null ? '${_n(value)} / ${_n(max!)}' : _n(value),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: atMax ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
