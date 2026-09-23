import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/active_company.dart';

/// CRUD + move-history service for a "lager" (inventory).
///
/// Two independent inventory systems exist — logistics and management —
/// each backed by its own pair of tables. This service is instantiated
/// once per system (see [logisticsInventoryService] / [mgmtInventoryService])
/// so the two never share data.
class InventoryService {
  final String itemsTable;
  final String movesTable;

  InventoryService({required this.itemsTable, required this.movesTable});

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _companyId => activeCompanyNotifier.value?.id;

  /// Bumped after any mutation so open pages can reload.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  void _bump() => refresh.value++;

  Future<List<Map<String, dynamic>>> listItems() async {
    final cid = _companyId;
    if (cid == null) return [];
    final rows = await _sb
        .from(itemsTable)
        .select('*')
        .eq('company_id', cid)
        .order('name');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<String?> createItem(Map<String, dynamic> data) async {
    final cid = _companyId;
    if (cid == null) return null;
    final user = _sb.auth.currentUser;
    final payload = <String, dynamic>{
      ...data,
      'company_id': cid,
      'created_by': user?.id,
      'updated_by': user?.id,
    };
    final res =
        await _sb.from(itemsTable).insert(payload).select('id').single();
    _bump();
    return res['id'] as String?;
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final user = _sb.auth.currentUser;
    await _sb.from(itemsTable).update({
      ...data,
      'updated_by': user?.id,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _bump();
  }

  Future<void> deleteItem(String id) async {
    await _sb.from(itemsTable).delete().eq('id', id);
    _bump();
  }

  /// Move [quantity] units of [item] to a new location, logging the move.
  ///
  /// - Moving the full quantity relocates the row (its history stays with it).
  /// - Moving a partial quantity leaves the remainder at the source and adds
  ///   the moved units to the destination — merging into an identical row
  ///   there if one exists, otherwise creating a new row.
  Future<void> moveItem({
    required Map<String, dynamic> item,
    required String toType,
    String? toRef,
    num? quantity,
    String? note,
  }) async {
    final cid = _companyId;
    final user = _sb.auth.currentUser;
    final id = item['id'] as String;

    final total = (item['quantity'] as num?) ?? 1;
    num moveQty = quantity ?? total;
    if (moveQty <= 0) moveQty = total;
    if (moveQty > total) moveQty = total;
    final movingAll = moveQty >= total;
    final moveCount = moveQty.floor();

    final srcSerials = _serialsOf(item);

    // Is this a container (does it have contents)?
    final childRows = await _sb.from(itemsTable).select('id').eq('parent_id', id);
    final hasChildren = (childRows as List).isNotEmpty;

    final stamp = {
      'updated_by': user?.id,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Log the move against the source item.
    await _sb.from(movesTable).insert({
      'company_id': cid,
      'item_id': id,
      'from_location_type': item['location_type'],
      'from_location_ref': item['location_ref'],
      'to_location_type': toType,
      'to_location_ref': toRef,
      'quantity': moveQty,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'moved_by': user?.id,
    });

    if (movingAll) {
      // A container never merges (that would orphan its contents) — it always
      // relocates as one unit. Otherwise merge into an identical row already at
      // the destination if one exists (e.g. moving everything back onto stock).
      final match = hasChildren
          ? null
          : await _findIdenticalAt(
              cid: cid,
              name: item['name'] as String? ?? '',
              category: item['category'] as String?,
              ref: item['ref_number'] as String?,
              unit: item['unit'] as String?,
              toType: toType,
              toRef: toRef,
              excludeId: id,
            );
      if (match != null) {
        final existing = (match['quantity'] as num?) ?? 0;
        final mergedSerials = [..._serialsOf(match), ...srcSerials];
        // Re-point this row's move history onto the surviving row so the
        // ON DELETE CASCADE below doesn't wipe it.
        await _sb.from(movesTable).update({'item_id': match['id']}).eq('item_id', id);
        await _sb.from(itemsTable).update({
          'quantity': existing + total,
          'serials': mergedSerials.isEmpty ? null : mergedSerials,
          ...stamp,
        }).eq('id', match['id']);
        await _sb.from(itemsTable).delete().eq('id', id);
      } else {
        await _sb.from(itemsTable).update({
          'location_type': toType,
          'location_ref': toRef,
          ...stamp,
        }).eq('id', id);
        // Move the container's contents along with it.
        if (hasChildren) {
          await _sb.from(itemsTable).update({
            'location_type': toType,
            'location_ref': toRef,
            ...stamp,
          }).eq('parent_id', id);
        }
      }
    } else {
      // Partial: split quantity AND serials between source and destination.
      final movedSerials = srcSerials.length > moveCount
          ? srcSerials.sublist(srcSerials.length - moveCount)
          : List<dynamic>.from(srcSerials);
      final remainingSerials = srcSerials.length > moveCount
          ? srcSerials.sublist(0, srcSerials.length - moveCount)
          : <dynamic>[];

      await _sb.from(itemsTable).update({
        'quantity': total - moveQty,
        'serials': remainingSerials.isEmpty ? null : remainingSerials,
        ...stamp,
      }).eq('id', id);

      // Add the moved units to the destination.
      final match = await _findIdenticalAt(
        cid: cid,
        name: item['name'] as String? ?? '',
        category: item['category'] as String?,
        ref: item['ref_number'] as String?,
        unit: item['unit'] as String?,
        toType: toType,
        toRef: toRef,
        excludeId: id,
      );
      if (match != null) {
        final existing = (match['quantity'] as num?) ?? 0;
        final mergedSerials = [..._serialsOf(match), ...movedSerials];
        await _sb.from(itemsTable).update({
          'quantity': existing + moveQty,
          'serials': mergedSerials.isEmpty ? null : mergedSerials,
          ...stamp,
        }).eq('id', match['id']);
      } else {
        await _sb.from(itemsTable).insert({
          'company_id': cid,
          'name': item['name'],
          'category': item['category'],
          'ref_number': item['ref_number'],
          'quantity': moveQty,
          'unit': item['unit'],
          'notes': item['notes'],
          // The split-off row keeps the same per-unit field definitions,
          // otherwise its units would read as untitled values.
          'unit_fields': item['unit_fields'],
          'serials': movedSerials.isEmpty ? null : movedSerials,
          'location_type': toType,
          'location_ref': toRef,
          'status': item['status'],
          'created_by': user?.id,
          'updated_by': user?.id,
        });
      }
    }

    _bump();
  }

  /// Put [itemId] inside container [parentId] (or take it out with null).
  /// When placed inside, its current location is synced to the container's.
  Future<void> setParent({
    required String itemId,
    String? parentId,
    String? locType,
    String? locRef,
  }) async {
    final data = <String, dynamic>{
      'parent_id': parentId,
      'updated_by': _sb.auth.currentUser?.id,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (parentId != null && locType != null) {
      data['location_type'] = locType;
      data['location_ref'] = locRef;
    }
    await _sb.from(itemsTable).update(data).eq('id', itemId);
    _bump();
  }

  /// Raw serial entries (each a `{sn, note}` map, or a legacy plain string).
  /// Returned untyped so split/merge preserves whatever shape is stored.
  static List<dynamic> _serialsOf(Map<String, dynamic> item) {
    final raw = item['serials'];
    if (raw is List) return List<dynamic>.from(raw);
    return const <dynamic>[];
  }

  /// Find an identical item (same name/category/ref/unit) already at the
  /// given destination, so partial moves merge instead of duplicating.
  Future<Map<String, dynamic>?> _findIdenticalAt({
    required String? cid,
    required String name,
    String? category,
    String? ref,
    String? unit,
    required String toType,
    String? toRef,
    required String excludeId,
  }) async {
    if (cid == null) return null;
    final rows = await _sb
        .from(itemsTable)
        .select('*')
        .eq('company_id', cid)
        .eq('name', name)
        .eq('location_type', toType);
    for (final r in List<Map<String, dynamic>>.from(rows as List)) {
      if (r['id'] == excludeId) continue;
      if (((r['location_ref'] as String?) ?? '') != (toRef ?? '')) continue;
      if (((r['category'] as String?) ?? '') != (category ?? '')) continue;
      if (((r['ref_number'] as String?) ?? '') != (ref ?? '')) continue;
      if (((r['unit'] as String?) ?? '') != (unit ?? '')) continue;
      return r;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listMoves(String itemId) async {
    final rows = await _sb
        .from(movesTable)
        .select('*')
        .eq('item_id', itemId)
        .order('moved_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}

// ── The two independent inventory systems ──────────────────────────────────

/// Logistics: parts/equipment distributed across buses/trucks.
final logisticsInventoryService = InventoryService(
  itemsTable: 'logistics_inventory_items',
  movesTable: 'logistics_inventory_moves',
);

/// Management: equipment overview + current location.
final mgmtInventoryService = InventoryService(
  itemsTable: 'mgmt_inventory_items',
  movesTable: 'mgmt_inventory_moves',
);
