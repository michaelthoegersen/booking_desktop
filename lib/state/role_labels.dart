import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_company.dart';

/// Per-company labels for the three crew role slots backed by the
/// `drummers`, `dancers` and `others` integer columns.
///
/// - role1 → drummers  (default "Trommeslagere")
/// - role2 → dancers   (default "Dansere")
/// - role3 → others    (default "Andre")
///
/// Stored in `companies.role_labels` (JSONB). Load is tied to
/// `activeCompanyNotifier` so pages just `ValueListenableBuilder` this.
class RoleLabels {
  final String role1;
  final String role2;
  final String role3;

  const RoleLabels({
    required this.role1,
    required this.role2,
    required this.role3,
  });

  static const defaults = RoleLabels(
    role1: 'Trommeslagere',
    role2: 'Dansere',
    role3: 'Andre',
  );

  factory RoleLabels.fromJson(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    return RoleLabels(
      role1: (m['role1'] as String?)?.trim().isNotEmpty == true
          ? m['role1'] as String
          : defaults.role1,
      role2: (m['role2'] as String?)?.trim().isNotEmpty == true
          ? m['role2'] as String
          : defaults.role2,
      role3: (m['role3'] as String?)?.trim().isNotEmpty == true
          ? m['role3'] as String
          : defaults.role3,
    );
  }

  Map<String, String> toJson() => {
        'role1': role1,
        'role2': role2,
        'role3': role3,
      };
}

class RoleLabelsNotifier extends ValueNotifier<RoleLabels> {
  RoleLabelsNotifier() : super(RoleLabels.defaults) {
    activeCompanyNotifier.addListener(_onCompanyChanged);
  }

  bool _disposed = false;

  void _onCompanyChanged() {
    refresh();
  }

  Future<void> refresh() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) {
      if (!_disposed) value = RoleLabels.defaults;
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('companies')
          .select('role_labels')
          .eq('id', companyId)
          .maybeSingle();
      final labels = RoleLabels.fromJson(row?['role_labels'] as Map<String, dynamic>?);
      if (!_disposed) value = labels;
    } catch (e) {
      debugPrint('RoleLabels refresh error: $e');
      if (!_disposed) value = RoleLabels.defaults;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    super.dispose();
  }
}

final roleLabelsNotifier = RoleLabelsNotifier();
