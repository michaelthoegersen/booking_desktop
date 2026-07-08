import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_field.dart';

class ProfileFieldService {
  static final _sb = Supabase.instance.client;

  /// Returns all sections + fields for a company, sorted by sort_order.
  static Future<List<ProfileField>> loadAll(String companyId) async {
    try {
      final rows = await _sb
          .from('profile_field_config')
          .select()
          .eq('company_id', companyId)
          .order('sort_order', ascending: true);
      return (rows as List)
          .map((e) => ProfileField.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ProfileFieldService.loadAll error: $e');
      return [];
    }
  }

  static Future<ProfileField?> insert(ProfileField f) async {
    try {
      final res = await _sb
          .from('profile_field_config')
          .insert(f.toInsert())
          .select()
          .single();
      return ProfileField.fromJson(res);
    } catch (e) {
      debugPrint('ProfileFieldService.insert error: $e');
      rethrow;
    }
  }

  static Future<void> update(ProfileField f) async {
    try {
      await _sb
          .from('profile_field_config')
          .update(f.toUpdate())
          .eq('id', f.id);
    } catch (e) {
      debugPrint('ProfileFieldService.update error: $e');
      rethrow;
    }
  }

  static Future<void> delete(String id) async {
    try {
      await _sb.from('profile_field_config').delete().eq('id', id);
    } catch (e) {
      debugPrint('ProfileFieldService.delete error: $e');
      rethrow;
    }
  }

  static Future<void> updateSortOrder(String id, int sortOrder) async {
    try {
      await _sb
          .from('profile_field_config')
          .update({'sort_order': sortOrder}).eq('id', id);
    } catch (e) {
      debugPrint('ProfileFieldService.updateSortOrder error: $e');
    }
  }
}
