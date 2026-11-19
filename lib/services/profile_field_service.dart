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

  /// The company's allergy field, whatever it was named.
  ///
  /// Allergies are not a column on `profiles` — they are one of the
  /// configurable profile fields each company sets up itself, and members
  /// fill them in from the mobile app. So the field is found by its title
  /// rather than by a fixed key, and a company that has not made one simply
  /// gets null.
  static ProfileField? allergyField(List<ProfileField> fields) {
    for (final f in fields) {
      if (f.isSection) continue;
      if (f.title.toLowerCase().contains('allerg')) return f;
    }
    return null;
  }

  /// One field's value for many people at once, as profile_id -> value.
  /// Used where a whole roster is shown and querying per person would be a
  /// request each.
  static Future<Map<String, String>> loadFieldForProfiles({
    required String fieldId,
    required List<String> profileIds,
  }) async {
    if (profileIds.isEmpty) return {};
    try {
      final rows = await _sb
          .from('profile_field_values')
          .select('profile_id, value')
          .eq('field_id', fieldId)
          .inFilter('profile_id', profileIds);
      final out = <String, String>{};
      for (final r in (rows as List)) {
        final pid = r['profile_id'] as String?;
        final v = (r['value'] as String?)?.trim();
        if (pid != null && v != null && v.isNotEmpty) out[pid] = v;
      }
      return out;
    } catch (e) {
      debugPrint('ProfileFieldService.loadFieldForProfiles error: $e');
      return {};
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
