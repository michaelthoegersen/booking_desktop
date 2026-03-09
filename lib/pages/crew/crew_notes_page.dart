import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';

/// Shows shared Dropbox folders that admin has made available to crew.
class CrewNotesPage extends StatefulWidget {
  const CrewNotesPage({super.key});

  @override
  State<CrewNotesPage> createState() => _CrewNotesPageState();
}

class _CrewNotesPageState extends State<CrewNotesPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _folders = [];

  String? get _companyId => activeCompanyNotifier.value?.id;

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
    if (_companyId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    try {
      final rows = await _sb
          .from('dropbox_shared_folders')
          .select()
          .eq('company_id', _companyId!)
          .order('sort_order', ascending: true);
      _folders = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('CrewNotesPage load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Noter & filer',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Delte filer fra admin — noter, partiturer og lydopptak.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_folders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.folder_off, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Ingen delte mapper ennå',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Admin har ikke delt noen mapper ennå.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _folders.length,
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  final displayName =
                      folder['display_name'] as String? ?? 'Mappe';
                  final dropboxPath = folder['dropbox_path'] as String? ?? '';

                  return GestureDetector(
                    onTap: () {
                      context.go(Uri(
                        path: '/c/notes/folder',
                        queryParameters: {
                          'path': dropboxPath,
                          'name': displayName,
                        },
                      ).toString());
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder, color: Colors.amber, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                          ),
                        ],
                      ),
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
