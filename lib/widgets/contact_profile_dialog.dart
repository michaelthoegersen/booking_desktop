import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_field.dart';
import '../services/profile_field_service.dart';
import '../state/active_company.dart';

/// Read-only modal that shows a contact's profile — basic info plus the
/// configurable profile fields the user has filled in via the mobile app.
class ContactProfileDialog extends StatefulWidget {
  final String contactId;
  final String contactName;
  final String? avatarUrl;

  const ContactProfileDialog({
    super.key,
    required this.contactId,
    required this.contactName,
    this.avatarUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required String contactId,
    required String contactName,
    String? avatarUrl,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ContactProfileDialog(
        contactId: contactId,
        contactName: contactName,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  State<ContactProfileDialog> createState() => _ContactProfileDialogState();
}

class _ContactProfileDialogState extends State<ContactProfileDialog> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _profile;
  List<ProfileField> _fields = [];
  Map<String, String> _values = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _sb
          .from('profiles')
          .select('name, role, section, email, phone, avatar_url')
          .eq('id', widget.contactId)
          .maybeSingle();
      _profile = p;

      final companyId = activeCompanyNotifier.value?.id;
      if (companyId != null) {
        _fields = await ProfileFieldService.loadAll(companyId);
        final rows = await _sb
            .from('profile_field_values')
            .select('field_id, value')
            .eq('profile_id', widget.contactId);
        final map = <String, String>{};
        for (final r in (rows as List)) {
          final fid = r['field_id'] as String?;
          final v = r['value'] as String?;
          if (fid != null && v != null) map[fid] = v;
        }
        _values = map;
      }
    } catch (e) {
      debugPrint('ContactProfileDialog load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _formatValue(ProfileField f, String raw) {
    switch (f.type) {
      case ProfileFieldType.bool_:
        return raw == 'true' ? 'Ja' : 'Nei';
      case ProfileFieldType.date:
        final d = DateTime.tryParse(raw);
        if (d == null) return raw;
        return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = widget.avatarUrl ??
        (_profile?['avatar_url'] as String?);
    final email = _profile?['email'] as String? ?? '';
    final phone = _profile?['phone'] as String? ?? '';
    final role = _profile?['role'] as String? ?? '';
    final section = _profile?['section'] as String? ?? '';

    final sections = _fields.where((f) => f.isSection).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        height: 640,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.black12,
                    backgroundImage:
                        avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? const Icon(Icons.person,
                            size: 28, color: Colors.black45)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.contactName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (role.isNotEmpty)
                          Text(
                            role,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Lukk',
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (email.isNotEmpty)
                            _readOnly('E-post', email, cs),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _readOnly('Telefon', phone, cs),
                          ],
                          if (section.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _readOnly('Seksjon', section, cs),
                          ],
                          ..._buildSections(sections, cs),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(
      List<ProfileField> sections, ColorScheme cs) {
    final widgets = <Widget>[];
    for (final s in sections) {
      final children = _fields.where((f) => f.parentId == s.id).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final filled = children
          .where((c) => (_values[c.id] ?? '').isNotEmpty)
          .toList();
      if (filled.isEmpty) continue;

      widgets.add(const SizedBox(height: 22));
      widgets.add(Text(
        s.title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ));
      widgets.add(const SizedBox(height: 8));
      for (final c in filled) {
        widgets.add(_readOnly(c.title, _formatValue(c, _values[c.id]!), cs));
        widgets.add(const SizedBox(height: 12));
      }
    }
    return widgets;
  }

  Widget _readOnly(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
