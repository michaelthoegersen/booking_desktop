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

  /// Item ids currently linked to the show identified by ([table], [column], [id]).
  static Future<Set<String>> linkedItemIds({
    required String table,
    required String column,
    required String id,
  }) async {
    final rows = await _sb.from(table).select('item_id').eq(column, id);
    return {for (final r in (rows as List)) r['item_id'] as String};
  }

  static Future<void> addLink({
    required String table,
    required String column,
    required String id,
    required String itemId,
  }) async {
    await _sb.from(table).upsert({
      column: id,
      'item_id': itemId,
      'company_id': _companyId,
      'created_by': _sb.auth.currentUser?.id,
    }, onConflict: '$column,item_id', ignoreDuplicates: true);
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
