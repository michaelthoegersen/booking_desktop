import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/active_company.dart';

/// Links between shows and equipment (mgmt inventory items).
///
/// Two link tables share the same shape, so this service is table-agnostic:
///   - fixed show:  table `show_type_equipment`, column `show_type_id`
///   - gig show:    table `gig_show_equipment`,  column `gig_show_id`
class ShowEquipmentService {
  static SupabaseClient get _sb => Supabase.instance.client;
  static String? get _companyId => activeCompanyNotifier.value?.id;

  static const String showTypeTable = 'show_type_equipment';
  static const String showTypeColumn = 'show_type_id';
  static const String gigShowTable = 'gig_show_equipment';
  static const String gigShowColumn = 'gig_show_id';

  /// Rows linked to the show ([table], [column], [id]) — {item_id, quantity, note}.
  static Future<List<Map<String, dynamic>>> linkedRows({
    required String table,
    required String column,
    required String id,
  }) async {
    final rows = await _sb
        .from(table)
        .select('item_id, quantity, note')
        .eq(column, id);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Link an item to the show (or update its quantity if already linked).
  /// Partial upsert: only [quantity] is written, so an existing note is kept.
  static Future<void> addLink({
    required String table,
    required String column,
    required String id,
    required String itemId,
    num quantity = 1,
  }) async {
    await _sb.from(table).upsert({
      column: id,
      'item_id': itemId,
      'company_id': _companyId,
      'quantity': quantity,
      'created_by': _sb.auth.currentUser?.id,
    }, onConflict: '$column,item_id');
  }

  /// Set (or clear) the per-link comment. Partial upsert keeps the quantity.
  static Future<void> setNote({
    required String table,
    required String column,
    required String id,
    required String itemId,
    String? note,
  }) async {
    final clean = (note == null || note.trim().isEmpty) ? null : note.trim();
    await _sb.from(table).upsert({
      column: id,
      'item_id': itemId,
      'company_id': _companyId,
      'note': clean,
    }, onConflict: '$column,item_id');
  }

  static Future<void> removeLink({
    required String table,
    required String column,
    required String id,
    required String itemId,
  }) async {
    await _sb.from(table).delete().eq(column, id).eq('item_id', itemId);
  }

  static Future<int> countForShowType(String showTypeId) async {
    final rows =
        await _sb.from(showTypeTable).select('id').eq(showTypeColumn, showTypeId);
    return (rows as List).length;
  }

  static Future<int> countForGigShow(String gigShowId) async {
    final rows =
        await _sb.from(gigShowTable).select('id').eq(gigShowColumn, gigShowId);
    return (rows as List).length;
  }
}
