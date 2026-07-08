import 'package:flutter/material.dart';

import '../../services/inventory_service.dart';
import '../../state/active_company.dart';
import '../../utils/company_vehicles.dart';
import 'inventory_common.dart';

/// Logistics "Lager" — parts/equipment distributed across the fleet.
/// Vehicle-centric: a warehouse bucket + one section per vehicle + venue.
class LogisticsInventoryPage extends StatefulWidget {
  const LogisticsInventoryPage({super.key});

  @override
  State<LogisticsInventoryPage> createState() =>
      _LogisticsInventoryPageState();
}

class _LogisticsInventoryPageState extends State<LogisticsInventoryPage> {
  final _service = logisticsInventoryService;
  static const _refLabel = 'Delenr. / serienr.';

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  List<String> _vehicles = [];

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
      final cfg = await loadVehicleConfig();
      final items = await _service.listItems();
      if (mounted) {
        setState(() {
          _vehicles = cfg.all;
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Logistics inventory load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ordered list of (title, type, ref, items) sections.
  List<_Section> get _sections {
    final sections = <_Section>[];

    List<Map<String, dynamic>> byLoc(String type, String? ref) => _items
        .where((it) =>
            (it['location_type'] as String? ?? kLocWarehouse) == type &&
            (ref == null ||
                ((it['location_ref'] as String?)?.trim() ?? '') == ref))
        .toList();

    // 1. Warehouse
    sections.add(_Section(
      title: 'Lager',
      type: kLocWarehouse,
      items: byLoc(kLocWarehouse, null),
    ));

    // 2. Known vehicles
    final knownRefs = <String>{};
    for (final v in _vehicles) {
      knownRefs.add(v);
      sections.add(_Section(
        title: v,
        type: kLocVehicle,
        items: byLoc(kLocVehicle, v),
      ));
    }

    // 3. Vehicle items assigned to a vehicle not in the config
    final orphanVehicleItems = _items.where((it) {
      if ((it['location_type'] as String?) != kLocVehicle) return false;
      final ref = (it['location_ref'] as String?)?.trim() ?? '';
      return ref.isEmpty || !knownRefs.contains(ref);
    }).toList();
    if (orphanVehicleItems.isNotEmpty) {
      sections.add(_Section(
        title: 'Andre kjøretøy',
        type: kLocVehicle,
        items: orphanVehicleItems,
      ));
    }

    // 4. Venue / other
    final venueItems = byLoc(kLocVenue, null);
    if (venueItems.isNotEmpty) {
      sections.add(_Section(
        title: 'Spillested / annet',
        type: kLocVenue,
        items: venueItems,
      ));
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lager',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Deler og utstyr fordelt på kjøretøy',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (await showInventoryItemDialog(context, _service,
                      refLabel: _refLabel)) {
                    _load();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Nytt utstyr'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'Ingen deler registrert ennå. Trykk «Nytt utstyr».',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final s in _sections) _sectionCard(context, s),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, _Section s) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Icon(locTypeIcon(s.type), color: cs.primary),
                const SizedBox(width: 10),
                Text(s.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${s.items.length}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          if (s.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ingen deler her',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 13)),
              ),
            )
          else
            ...s.items.map((it) => _itemRow(context, it)),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final category = (item['category'] as String?)?.trim();
    final ref = (item['ref_number'] as String?)?.trim();
    final sub = [
      if (category != null && category.isNotEmpty) category,
      fmtQty(item),
      if (ref != null && ref.isNotEmpty) 'nr. $ref',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 6, 6),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.build_circle_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (sub.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(sub,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              inventoryActionsMenu(
                context: context,
                item: item,
                service: _service,
                refLabel: _refLabel,
                onChanged: _load,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section {
  final String title;
  final String type;
  final List<Map<String, dynamic>> items;
  _Section({required this.title, required this.type, required this.items});
}
