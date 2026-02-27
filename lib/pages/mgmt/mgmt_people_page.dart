import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';
import '../../ui/css_theme.dart';

class MgmtPeoplePage extends StatefulWidget {
  const MgmtPeoplePage({super.key});

  @override
  State<MgmtPeoplePage> createState() => _MgmtPeoplePageState();
}

class _MgmtPeoplePageState extends State<MgmtPeoplePage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? get _companyId => activeCompanyNotifier.value?.id;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    super.dispose();
  }

  void _onCompanyChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_companyId == null) {
        setState(() => _loading = false);
        return;
      }

      // Get all team members across all tours for this company
      final tourIds = await _sb
          .from('management_tours')
          .select('id')
          .eq('company_id', _companyId!);
      final ids = (tourIds as List).map((t) => t['id'] as String).toList();

      if (ids.isNotEmpty) {
        final people = await _sb
            .from('management_team')
            .select('*, management_tours!inner(name)')
            .inFilter('tour_id', ids)
            .order('name');
        _people = List<Map<String, dynamic>>.from(people);
      } else {
        _people = [];
      }
    } catch (e) {
      debugPrint('People load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'People',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'All team members across your tours',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CssTheme.textMuted,
                ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _people.isEmpty
                    ? const Center(
                        child: Text(
                          'No people yet. Add team members to your tours.',
                          style: TextStyle(color: CssTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _people.length,
                        itemBuilder: (context, i) {
                          final person = _people[i];
                          final name = person['name'] as String? ?? '';
                          final role = person['role'] as String? ?? '';
                          final email = person['email'] as String? ?? '';
                          final phone = person['phone'] as String? ?? '';
                          final tour = person['management_tours']
                              as Map<String, dynamic>?;
                          final tourName = tour?['name'] as String? ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: CssTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: CssTheme.outline),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.black,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                      Text(
                                        [
                                          role.replaceAll('_', ' '),
                                          if (tourName.isNotEmpty) tourName,
                                        ].join(' · '),
                                        style: const TextStyle(
                                            color: CssTheme.textMuted),
                                      ),
                                      if (email.isNotEmpty ||
                                          phone.isNotEmpty)
                                        Text(
                                          [email, phone]
                                              .where((s) => s.isNotEmpty)
                                              .join(' · '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: CssTheme.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
