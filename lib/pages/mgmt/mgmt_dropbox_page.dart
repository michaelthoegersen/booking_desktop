import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/dropbox_oauth_service.dart';
import '../../state/active_company.dart';
class MgmtDropboxPage extends StatefulWidget {
  const MgmtDropboxPage({super.key});

  @override
  State<MgmtDropboxPage> createState() => _MgmtDropboxPageState();
}

class _MgmtDropboxPageState extends State<MgmtDropboxPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _connected = false;
  String? _accountName;
  List<Map<String, dynamic>> _sharedFolders = [];
  bool _connecting = false;

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
      // Check status via edge function
      final status = await DropboxOAuthService.status();
      _connected = status['connected'] == true;
      _accountName = status['account_name'] as String?;

      // Load shared folders
      if (_connected) {
        final folders = await _sb
            .from('dropbox_shared_folders')
            .select()
            .eq('company_id', _companyId!)
            .order('sort_order', ascending: true);
        _sharedFolders = List<Map<String, dynamic>>.from(folders);
      } else {
        _sharedFolders = [];
      }
    } catch (e) {
      debugPrint('MgmtDropboxPage load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connectDropbox() async {
    setState(() => _connecting = true);
    try {
      final ok = await DropboxOAuthService.connect(appKey: 'bvlqrmh6watlaiq');
      if (ok) await _load();
    } catch (e) {
      debugPrint('Connect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tilkobling feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnectDropbox() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koble fra Dropbox?'),
        content: const Text(
          'Alle delte mapper vil bli fjernet. Crew mister tilgang til filene.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Koble fra'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await DropboxOAuthService.disconnect();
      await _load();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }

  Future<void> _addSharedFolder() async {
    // Show folder browser dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _FolderPickerDialog(companyId: _companyId!),
    );
    if (result == null) return;

    final path = result['path']!;
    final displayName = result['display_name'] ?? path.split('/').last;

    try {
      await _sb.from('dropbox_shared_folders').insert({
        'company_id': _companyId!,
        'dropbox_path': path,
        'display_name': displayName,
        'sort_order': _sharedFolders.length,
      });
      await _load();
    } catch (e) {
      debugPrint('Add folder error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke legge til mappe: $e')),
        );
      }
    }
  }

  Future<void> _removeSharedFolder(String folderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern delt mappe?'),
        content: const Text('Crew vil ikke lenger se denne mappen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _sb.from('dropbox_shared_folders').delete().eq('id', folderId);
      await _load();
    } catch (e) {
      debugPrint('Remove folder error: $e');
    }
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dropbox',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Del noter, partiturer og lydfiler med crew.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 28),

          // Connection status card
          _buildConnectionCard(),

          // Shared folders (only when connected)
          if (_connected) ...[
            const SizedBox(height: 28),
            _buildSharedFoldersSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _connected ? _buildConnectedState() : _buildDisconnectedState(),
    );
  }

  Widget _buildDisconnectedState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.cloud_off, size: 28, color: Colors.grey),
            SizedBox(width: 12),
            Text(
              'Ikke tilkoblet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Koble til Dropbox for å dele filer med crew-medlemmer. '
          'Du velger selv hvilke mapper som deles.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _connecting ? null : _connectDropbox,
          icon: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_outlined),
          label: Text(_connecting ? 'Kobler til...' : 'Koble til Dropbox'),
        ),
      ],
    );
  }

  Widget _buildConnectedState() {
    return Row(
      children: [
        const Icon(Icons.cloud_done, size: 28, color: Colors.green),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tilkoblet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_accountName != null && _accountName!.isNotEmpty)
                Text(
                  _accountName!,
                  style: TextStyle(color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: _disconnectDropbox,
          child: const Text('Koble fra'),
        ),
      ],
    );
  }

  Widget _buildSharedFoldersSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Delte mapper',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addSharedFolder,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Legg til mappe'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Disse mappene er synlige for alle crew-medlemmer i appen.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        if (_sharedFolders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: const Center(
              child: Text(
                'Ingen mapper delt ennå. Legg til en mappe for å komme i gang.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...List.generate(_sharedFolders.length, (i) {
            final folder = _sharedFolders[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder['display_name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          folder['dropbox_path'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Fjern',
                    onPressed: () =>
                        _removeSharedFolder(folder['id'] as String),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// FOLDER PICKER DIALOG
// ══════════════════════════════════════════════════════════════

class _FolderPickerDialog extends StatefulWidget {
  final String companyId;

  const _FolderPickerDialog({required this.companyId});

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  String _currentPath = '';
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _selectedPath;
  final _displayNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFolder('');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadFolder(String path) async {
    setState(() {
      _loading = true;
      _currentPath = path;
      _selectedPath = null;
    });

    try {
      final entries = await DropboxOAuthService.listFolder(path);
      // Show only folders
      _entries = entries.where((e) => e['is_folder'] == true).toList();
    } catch (e) {
      debugPrint('Folder picker error: $e');
      _entries = [];
    }

    if (mounted) setState(() => _loading = false);
  }

  void _selectCurrentFolder() {
    if (_currentPath.isEmpty) return;

    final defaultName = _currentPath.split('/').last;
    _displayNameController.text = defaultName;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Visningsnavn'),
        content: TextField(
          controller: _displayNameController,
          decoration: const InputDecoration(
            labelText: 'Navn som vises for crew',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, {
                'path': _currentPath,
                'display_name': _displayNameController.text.trim().isNotEmpty
                    ? _displayNameController.text.trim()
                    : defaultName,
              });
            },
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pathParts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();

    return Dialog(
      child: SizedBox(
        width: 500,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Velg mappe',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Breadcrumb
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _loadFolder(''),
                      child: const Text(
                        'Dropbox',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (var i = 0; i < pathParts.length; i++) ...[
                      const Text(' / '),
                      InkWell(
                        onTap: () {
                          final newPath =
                              '/${pathParts.sublist(0, i + 1).join('/')}';
                          _loadFolder(newPath);
                        },
                        child: Text(
                          pathParts[i],
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Folder list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _entries.isEmpty
                        ? const Center(
                            child: Text(
                              'Ingen undermapper',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (context, index) {
                              final entry = _entries[index];
                              final name = entry['name'] as String;
                              final path = entry['path'] as String;

                              return ListTile(
                                leading: const Icon(
                                  Icons.folder,
                                  color: Colors.amber,
                                ),
                                title: Text(name),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                ),
                                onTap: () => _loadFolder(path),
                              );
                            },
                          ),
              ),

              const SizedBox(height: 12),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Avbryt'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _currentPath.isNotEmpty ? _selectCurrentFolder : null,
                    child: Text(
                      _currentPath.isEmpty
                          ? 'Velg en mappe'
                          : 'Velg denne mappen',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
