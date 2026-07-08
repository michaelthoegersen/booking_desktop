import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/inventory_service.dart';
import '../../utils/company_vehicles.dart';

/// Capitalises the first letter of a text field as you type (works on
/// desktop too, where `textCapitalization` alone has no effect).
class CapitalizeFirstFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final first = text[0].toUpperCase();
    if (first == text[0]) return newValue;
    return TextEditingValue(
      text: first + text.substring(1),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Shared formatter list + capitalization for every writable field.
final List<TextInputFormatter> kCapFirst = [CapitalizeFirstFormatter()];

// ── Location constants ─────────────────────────────────────────────────────

const String kLocWarehouse = 'warehouse';
const String kLocVehicle = 'vehicle';
const String kLocVenue = 'venue';

const List<String> kLocTypes = [kLocWarehouse, kLocVehicle, kLocVenue];

String locTypeLabel(String type) {
  switch (type) {
    case kLocVehicle:
      return 'Kjøretøy';
    case kLocVenue:
      return 'Spillested';
    default:
      return 'Lager';
  }
}

IconData locTypeIcon(String type) {
  switch (type) {
    case kLocVehicle:
      return Icons.local_shipping_rounded;
    case kLocVenue:
      return Icons.location_on_rounded;
    default:
      return Icons.warehouse_rounded;
  }
}

/// Human label for where an item currently is (ref if present, else type).
String locDisplay(Map<String, dynamic> item) {
  final t = (item['location_type'] as String?) ?? kLocWarehouse;
  final ref = (item['location_ref'] as String?)?.trim() ?? '';
  if (ref.isNotEmpty) return ref;
  return locTypeLabel(t);
}

String fmtQty(Map<String, dynamic> item) {
  final q = item['quantity'];
  final unit = (item['unit'] as String?)?.trim();
  final qStr = q == null
      ? '1'
      : (q is num && q == q.roundToDouble() ? q.toInt().toString() : '$q');
  return unit == null || unit.isEmpty ? qStr : '$qStr $unit';
}

/// Small pill showing an item's current location.
Widget locationPill(BuildContext context, Map<String, dynamic> item) {
  final cs = Theme.of(context).colorScheme;
  final t = (item['location_type'] as String?) ?? kLocWarehouse;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(locTypeIcon(t), size: 14, color: cs.onSecondaryContainer),
        const SizedBox(width: 5),
        Text(
          locDisplay(item),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSecondaryContainer,
          ),
        ),
      ],
    ),
  );
}

// ── Location picker (type chips + ref field / vehicle dropdown) ─────────────

class LocationPicker extends StatefulWidget {
  final String initialType;
  final String? initialRef;
  final List<String> allowedTypes;
  final void Function(String type, String? ref) onChanged;

  const LocationPicker({
    super.key,
    required this.initialType,
    this.initialRef,
    this.allowedTypes = kLocTypes,
    required this.onChanged,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late String _type;
  String? _ref;
  final _refCtrl = TextEditingController();
  List<String> _vehicles = [];

  @override
  void initState() {
    super.initState();
    _type = widget.allowedTypes.contains(widget.initialType)
        ? widget.initialType
        : widget.allowedTypes.first;
    _ref = _type == widget.initialType ? widget.initialRef : null;
    _refCtrl.text = _ref ?? '';
    // If the initial type wasn't allowed, tell the parent about the fallback.
    if (_type != widget.initialType) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
    if (widget.allowedTypes.contains(kLocVehicle)) _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    final cfg = await loadVehicleConfig();
    if (!mounted) return;
    setState(() => _vehicles = cfg.all);
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final r = _ref?.trim();
    widget.onChanged(_type, (r == null || r.isEmpty) ? null : r);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: widget.allowedTypes.map((t) {
            return ChoiceChip(
              label: Text(locTypeLabel(t)),
              avatar: Icon(locTypeIcon(t), size: 16),
              selected: t == _type,
              onSelected: (_) => setState(() {
                _type = t;
                _ref = null;
                _refCtrl.clear();
                _emit();
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_type == kLocVehicle)
          DropdownButtonFormField<String>(
            initialValue: _vehicles.contains(_ref) ? _ref : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Velg kjøretøy',
              border: OutlineInputBorder(),
            ),
            items: _vehicles
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() {
              _ref = v;
              _emit();
            }),
          )
        else
          TextField(
            controller: _refCtrl,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: kCapFirst,
            decoration: InputDecoration(
              labelText: _type == kLocVenue
                  ? 'Spillested / sted'
                  : 'Lagernavn (valgfritt)',
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              _ref = v;
              _emit();
            },
          ),
      ],
    );
  }
}

// ── Add / edit item dialog ──────────────────────────────────────────────────

/// Returns true if the item was created/updated.
Future<bool> showInventoryItemDialog(
  BuildContext context,
  InventoryService service, {
  Map<String, dynamic>? item,
  String refLabel = 'Referanse / serienr.',
  List<String> locationTypes = kLocTypes,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => _InventoryItemDialog(
      service: service,
      item: item,
      refLabel: refLabel,
      locationTypes: locationTypes,
    ),
  );
  return res ?? false;
}

class _InventoryItemDialog extends StatefulWidget {
  final InventoryService service;
  final Map<String, dynamic>? item;
  final String refLabel;
  final List<String> locationTypes;

  const _InventoryItemDialog({
    required this.service,
    this.item,
    required this.refLabel,
    required this.locationTypes,
  });

  @override
  State<_InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends State<_InventoryItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _ref;
  late final TextEditingController _qty;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  String _locType = kLocWarehouse;
  String? _locRef;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _name = TextEditingController(text: it?['name'] as String? ?? '');
    _category = TextEditingController(text: it?['category'] as String? ?? '');
    _ref = TextEditingController(text: it?['ref_number'] as String? ?? '');
    _qty = TextEditingController(text: (it?['quantity'] ?? 1).toString());
    _unit = TextEditingController(text: it?['unit'] as String? ?? 'stk');
    _notes = TextEditingController(text: it?['notes'] as String? ?? '');
    _locType = it?['location_type'] as String? ?? kLocWarehouse;
    if (!widget.locationTypes.contains(_locType)) {
      _locType = widget.locationTypes.first;
      _locRef = null;
    } else {
      _locRef = it?['location_ref'] as String?;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _ref.dispose();
    _qty.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'name': name,
      'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
      'ref_number': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      'quantity':
          num.tryParse(_qty.text.trim().replaceAll(',', '.')) ?? 1,
      'unit': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };

    try {
      if (_isEdit) {
        await widget.service.updateItem(widget.item!['id'] as String, data);
      } else {
        data['location_type'] = _locType;
        data['location_ref'] = _locRef;
        await widget.service.createItem(data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lagring feilet: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Rediger utstyr' : 'Nytt utstyr'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: kCapFirst,
                decoration: const InputDecoration(
                    labelText: 'Navn *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: kCapFirst,
                decoration: const InputDecoration(
                    labelText: 'Kategori', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ref,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: kCapFirst,
                decoration: InputDecoration(
                    labelText: widget.refLabel,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Antall', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: kCapFirst,
                      decoration: const InputDecoration(
                          labelText: 'Enhet', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: kCapFirst,
                decoration: const InputDecoration(
                    labelText: 'Notat', border: OutlineInputBorder()),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Plassering',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                LocationPicker(
                  initialType: _locType,
                  initialRef: _locRef,
                  allowedTypes: widget.locationTypes,
                  onChanged: (t, r) {
                    _locType = t;
                    _locRef = r;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Lagrer…' : 'Lagre'),
        ),
      ],
    );
  }
}

// ── Move dialog ─────────────────────────────────────────────────────────────

/// Returns true if the item was moved.
Future<bool> showMoveDialog(
  BuildContext context,
  InventoryService service,
  Map<String, dynamic> item, {
  List<String> locationTypes = kLocTypes,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _MoveDialog(service: service, item: item, locationTypes: locationTypes),
  );
  return res ?? false;
}

class _MoveDialog extends StatefulWidget {
  final InventoryService service;
  final Map<String, dynamic> item;
  final List<String> locationTypes;

  const _MoveDialog({
    required this.service,
    required this.item,
    required this.locationTypes,
  });

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late String _type;
  String? _ref;
  late final num _total;
  late final TextEditingController _qtyCtrl;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.item['location_type'] as String? ?? kLocWarehouse;
    _ref = widget.item['location_ref'] as String?;
    _total = (widget.item['quantity'] as num?) ?? 1;
    _qtyCtrl = TextEditingController(text: _numStr(_total));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _numStr(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : '$n';

  Future<void> _save() async {
    num qty = num.tryParse(_qtyCtrl.text.trim().replaceAll(',', '.')) ?? _total;
    if (qty <= 0) qty = _total;
    if (qty > _total) qty = _total;

    setState(() => _saving = true);
    try {
      await widget.service.moveItem(
        item: widget.item,
        toType: _type,
        toRef: _ref,
        quantity: qty,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Flytting feilet: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Flytt: ${widget.item['name'] ?? ''}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Nå: ',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  locationPill(context, widget.item),
                ],
              ),
              if (_total > 1) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Antall som flyttes (av ${_numStr(_total)})',
                    helperText: 'Resten blir liggende igjen',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Ny plassering',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              LocationPicker(
                initialType: _type,
                initialRef: _ref,
                allowedTypes: widget.locationTypes,
                onChanged: (t, r) {
                  _type = t;
                  _ref = r;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: kCapFirst,
                decoration: const InputDecoration(
                    labelText: 'Notat (valgfritt)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Flytter…' : 'Flytt'),
        ),
      ],
    );
  }
}

// ── History sheet ───────────────────────────────────────────────────────────

Future<void> showHistorySheet(
  BuildContext context,
  InventoryService service,
  Map<String, dynamic> item,
) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _HistorySheet(service: service, item: item),
  );
}

class _HistorySheet extends StatefulWidget {
  final InventoryService service;
  final Map<String, dynamic> item;

  const _HistorySheet({required this.service, required this.item});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _moves = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.service.listMoves(widget.item['id'] as String);
      if (mounted) {
        setState(() {
          _moves = m;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Historikk — ${widget.item['name'] ?? ''}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Nåværende plassering: ${locDisplay(widget.item)}',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_moves.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Ingen flyttinger registrert ennå.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _moves.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (_, i) {
                      final m = _moves[i];
                      final fromT =
                          m['from_location_type'] as String? ?? kLocWarehouse;
                      final toT =
                          m['to_location_type'] as String? ?? kLocWarehouse;
                      final fromRef =
                          (m['from_location_ref'] as String?)?.trim();
                      final toRef = (m['to_location_ref'] as String?)?.trim();
                      final from = (fromRef == null || fromRef.isEmpty)
                          ? locTypeLabel(fromT)
                          : fromRef;
                      final to = (toRef == null || toRef.isEmpty)
                          ? locTypeLabel(toT)
                          : toRef;
                      final note = (m['note'] as String?)?.trim();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(locTypeIcon(fromT),
                                  size: 16, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(child: Text(from)),
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward, size: 16),
                              ),
                              Icon(locTypeIcon(toT),
                                  size: 16, color: cs.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(to,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(_fmtDate(m['moved_at'] as String?),
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          if (note != null && note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(note,
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic)),
                            ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared row actions menu ─────────────────────────────────────────────────

enum InventoryAction { move, history, edit, delete }

/// A trailing "⋮" menu with Flytt / Historikk / Rediger / Slett.
Widget inventoryActionsMenu({
  required BuildContext context,
  required Map<String, dynamic> item,
  required InventoryService service,
  required String refLabel,
  required VoidCallback onChanged,
  List<String> locationTypes = kLocTypes,
}) {
  return PopupMenuButton<InventoryAction>(
    tooltip: 'Handlinger',
    onSelected: (action) async {
      switch (action) {
        case InventoryAction.move:
          if (await showMoveDialog(context, service, item,
              locationTypes: locationTypes)) {
            onChanged();
          }
          break;
        case InventoryAction.history:
          await showHistorySheet(context, service, item);
          break;
        case InventoryAction.edit:
          if (await showInventoryItemDialog(context, service,
              item: item, refLabel: refLabel, locationTypes: locationTypes)) {
            onChanged();
          }
          break;
        case InventoryAction.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Slette utstyr?'),
              content: Text(
                  'Vil du slette "${item['name'] ?? ''}"? Historikken slettes også.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Avbryt')),
                FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Slett')),
              ],
            ),
          );
          if (ok == true) {
            await service.deleteItem(item['id'] as String);
            onChanged();
          }
          break;
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: InventoryAction.move,
        child: Row(children: [
          Icon(Icons.swap_horiz_rounded, size: 18),
          SizedBox(width: 8),
          Text('Flytt'),
        ]),
      ),
      PopupMenuItem(
        value: InventoryAction.history,
        child: Row(children: [
          Icon(Icons.history_rounded, size: 18),
          SizedBox(width: 8),
          Text('Historikk'),
        ]),
      ),
      PopupMenuItem(
        value: InventoryAction.edit,
        child: Row(children: [
          Icon(Icons.edit_outlined, size: 18),
          SizedBox(width: 8),
          Text('Rediger'),
        ]),
      ),
      PopupMenuItem(
        value: InventoryAction.delete,
        child: Row(children: [
          Icon(Icons.delete_outline_rounded, size: 18),
          SizedBox(width: 8),
          Text('Slett'),
        ]),
      ),
    ],
  );
}
