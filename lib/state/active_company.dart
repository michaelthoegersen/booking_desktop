import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActiveCompany {
  final String id;
  final String name;
  final String role;

  const ActiveCompany({
    required this.id,
    required this.name,
    required this.role,
  });
}

class ActiveCompanyNotifier extends ValueNotifier<ActiveCompany?> {
  ActiveCompanyNotifier() : super(null);

  List<ActiveCompany> _companies = [];

  List<ActiveCompany> get companies => List.unmodifiable(_companies);

  Future<void> load() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      _companies = [];
      value = null;
      return;
    }

    final list = <ActiveCompany>[];

    // Try company_members first
    try {
      final rows = await sb
          .from('company_members')
          .select('company_id, role, companies(name)')
          .eq('user_id', uid);

      for (final r in (rows as List)) {
        final companyId = r['company_id'] as String?;
        final company = r['companies'] as Map<String, dynamic>?;
        final name = company?['name'] as String? ?? '';
        final role = r['role'] as String? ?? 'bruker';
        if (companyId != null) {
          list.add(ActiveCompany(id: companyId, name: name, role: role));
        }
      }
    } catch (e) {
      debugPrint('company_members query failed (fallback to profiles): $e');
    }

    // Fallback: if no rows from company_members, use profiles.company_id
    if (list.isEmpty) {
      try {
        final profile = await sb
            .from('profiles')
            .select('company_id, role')
            .eq('id', uid)
            .maybeSingle();
        final companyId = profile?['company_id'] as String?;
        if (companyId != null) {
          final company = await sb
              .from('companies')
              .select('name')
              .eq('id', companyId)
              .maybeSingle();
          list.add(ActiveCompany(
            id: companyId,
            name: company?['name'] as String? ?? '',
            role: profile?['role'] as String? ?? 'bruker',
          ));
        }
      } catch (e) {
        debugPrint('ActiveCompanyNotifier profiles fallback error: $e');
      }
    }

    _companies = list;

    // Keep current selection if still valid, otherwise pick first
    if (value != null && list.any((c) => c.id == value!.id)) {
      value = list.firstWhere((c) => c.id == value!.id);
    } else {
      value = list.isNotEmpty ? list.first : null;
    }
  }

  void switchTo(String companyId) {
    final match = _companies.where((c) => c.id == companyId);
    if (match.isNotEmpty) {
      value = match.first;
    }
  }

  void clear() {
    _companies = [];
    value = null;
  }
}

final activeCompanyNotifier = ActiveCompanyNotifier();
