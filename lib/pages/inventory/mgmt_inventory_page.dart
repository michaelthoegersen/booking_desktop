import 'package:flutter/material.dart';

import '../../services/inventory_service.dart';
import '../../state/active_company.dart';
import 'container_contents_dialog.dart';
import 'inventory_common.dart';

/// Management inventory is never assigned to a vehicle — only Lager / Spillested.
const List<String> _mgmtLocationTypes = [kLocWarehouse, kLocVenue];

/// Management "Lager" — overview of all equipment and where it is right now.
class MgmtInventoryPage extends StatefulWidget {
  const MgmtInventoryPage({super.key});

  @override
  State<MgmtInventoryPage> createState() => _MgmtInventoryPageState();
}

class _MgmtInventoryPageState extends State<MgmtInventoryPage> {
  final _service = mgmtInventoryService;
  static const _refLabel = 'Serienr.';

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _search = '';
  String? _filterType; // null = all
  final Set<String> _expanded = {}; // item ids whose units are shown

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_load);
    _service.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_load);
    _service.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final items = await _service.listItems();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Mgmt inventory load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _childrenOf(String id) =>
      _items.where((it) => it['parent_id'] == id).toList();

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _items.where((it) {
      // Contents of a container are shown nested under it, not as top rows.
      if (it['parent_id'] != null) return false;
      if (_filterType != null && it['location_type'] != _filterType) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        it['name'],
        it['category'],
        it['ref_number'],
        it['location_ref'],
      ].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lager', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Oversikt over utstyr og hvor det er til enhver tid',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),

          // Toolbar
          Row(
            children: [
              Expanded(
                child: TextField(
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: kCapFirst,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Søk etter navn, kategori, serienr…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _filterType,
                hint: const Text('Alle plasseringer'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle plasseringer')),
                  ..._mgmtLocationTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(locTypeLabel(t)),
                      )),
                ],
                onChanged: (v) => setState(() => _filterType = v),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () async {
                  if (await showInventoryItemDialog(context, _service,
                      refLabel: _refLabel,
                      locationTypes: _mgmtLocationTypes)) {
                    _load();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Nytt utstyr'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          _items.isEmpty
                              ? 'Ingen utstyr registrert ennå. Trykk «Nytt utstyr».'
                              : 'Ingen treff.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) =>
                            _itemRow(context, items[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final id = item['id'] as String;
    final category = (item['category'] as String?)?.trim();
    final ref = (item['ref_number'] as String?)?.trim();
    final serialUnits = ((item['serials'] as List?) ?? const []).map((e) {
      if (e is Map) {
        return (
          sn: (e['sn'] ?? '').toString(),
          note: (e['note'] ?? '').toString(),
        );
      }
      return (sn: e.toString(), note: '');
    }).toList();
    final children = _childrenOf(id);
    final qtyInt = ((item['quantity'] as num?) ?? 1).floor();
    final expandable = qtyInt > 1 || serialUnits.isNotEmpty;
    final expanded = _expanded.contains(id);
    final sub = [
      if (category != null && category.isNotEmpty) category,
      fmtQty(item),
      if (ref != null && ref.isNotEmpty) 'nr. $ref',
      if (children.isNotEmpty) 'Inneholder ${children.length}',
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(children.isNotEmpty
                      ? Icons.inventory_rounded
                      : Icons.inventory_2_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'] as String? ?? '',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      if (sub.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(sub,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: expandable
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                              expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 22),
                          tooltip:
                              expanded ? 'Skjul enheter' : 'Vis enheter',
                          onPressed: () => setState(() {
                            if (expanded) {
                              _expanded.remove(id);
                            } else {
                              _expanded.add(id);
                            }
                          }),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                locationPill(context, item),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.account_tree_outlined, size: 20),
                  tooltip: 'Innhold i enhet',
                  onPressed: () async {
                    await showContainerContentsDialog(context, _service, item);
                    _load();
                  },
                ),
                inventoryActionsMenu(
                  context: context,
                  item: item,
                  service: _service,
                  refLabel: _refLabel,
                  onChanged: _load,
                  locationTypes: _mgmtLocationTypes,
                ),
              ],
            ),
            if (expandable && expanded)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4, bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(
                    qtyInt > serialUnits.length ? qtyInt : serialUnits.length,
                    (i) {
                      final sn =
                          i < serialUnits.length ? serialUnits[i].sn.trim() : '';
                      final note = i < serialUnits.length
                          ? serialUnits[i].note.trim()
                          : '';
                      final hasSn = sn.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.tag,
                                size: 15, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 62,
                              child: Text('Enhet ${i + 1}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant)),
                            ),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: hasSn ? sn : 'uten serienr.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: hasSn
                                            ? cs.onSurface
                                            : cs.onSurfaceVariant,
                                        fontStyle: hasSn
                                            ? FontStyle.normal
                                            : FontStyle.italic,
                                      ),
                                    ),
                                    if (note.isNotEmpty)
                                      TextSpan(
                                        text: '  ·  $note',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          color: cs.primary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4, bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children.map((c) {
                    final ccat = (c['category'] as String?)?.trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.subdirectory_arrow_right,
                              size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                c['name'] as String? ?? '',
                                if (ccat != null && ccat.isNotEmpty) ccat,
                                fmtQty(c),
                              ].join('  ·  '),
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
