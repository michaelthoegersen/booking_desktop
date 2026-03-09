import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';

/// Browses a Dropbox folder via edge function. Supports navigating subfolders
/// and opening files (PDF via temp download, audio via player screen).
class CrewFolderBrowserPage extends StatefulWidget {
  final String folderPath;
  final String folderName;

  const CrewFolderBrowserPage({
    super.key,
    required this.folderPath,
    required this.folderName,
  });

  @override
  State<CrewFolderBrowserPage> createState() => _CrewFolderBrowserPageState();
}

class _CrewFolderBrowserPageState extends State<CrewFolderBrowserPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];
  String? _openingFile;

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_companyId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    try {
      final res = await _sb.functions.invoke('dropbox-list-folder', body: {
        'company_id': _companyId!,
        'path': widget.folderPath,
      });

      final data = res.data as Map<String, dynamic>?;
      final entries = data?['entries'] as List?;
      _entries =
          entries?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
              [];
    } catch (e) {
      debugPrint('FolderBrowser load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openFile(Map<String, dynamic> entry) async {
    final path = entry['path'] as String;
    final name = entry['name'] as String;
    final ext = name.split('.').last.toLowerCase();

    // Audio files → go to audio player
    if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'].contains(ext)) {
      context.go(Uri(
        path: '/c/notes/audio',
        queryParameters: {'path': path, 'name': name},
      ).toString());
      return;
    }

    // All other files → get temp link and download/open
    setState(() => _openingFile = path);
    try {
      final res = await _sb.functions.invoke('dropbox-get-temp-link', body: {
        'company_id': _companyId!,
        'path': path,
      });

      final data = res.data as Map<String, dynamic>?;
      final link = data?['link'] as String?;
      if (link == null) throw Exception('No link received');

      // Download to temp directory and open
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$name';
      final response = await http.get(Uri.parse(link));

      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        await OpenFilex.open(filePath);
      } else {
        throw Exception('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Open file error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke åpne filen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFile = null);
    }
  }

  IconData _iconForEntry(Map<String, dynamic> entry) {
    if (entry['is_folder'] == true) return Icons.folder;

    final name = (entry['name'] as String? ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.aac') ||
        name.endsWith('.flac') ||
        name.endsWith('.ogg') ||
        name.endsWith('.m4a')) {
      return Icons.audiotrack;
    }
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Icons.image;
    }
    return Icons.insert_drive_file;
  }

  Color _iconColorForEntry(Map<String, dynamic> entry) {
    if (entry['is_folder'] == true) return Colors.amber;

    final name = (entry['name'] as String? ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return Colors.red;
    if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.aac') ||
        name.endsWith('.flac') ||
        name.endsWith('.ogg') ||
        name.endsWith('.m4a')) {
      return Colors.purple;
    }
    return Colors.blueGrey;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + title
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/c/notes'),
                tooltip: 'Tilbake',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.folderName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_entries.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text(
                      'Ingen filer i denne mappen',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final name = entry['name'] as String? ?? '';
                  final path = entry['path'] as String? ?? '';
                  final isFolder = entry['is_folder'] == true;
                  final size = entry['size'] as int? ?? 0;
                  final isOpening = _openingFile == path;

                  return GestureDetector(
                    onTap: () {
                      if (isFolder) {
                        context.go(Uri(
                          path: '/c/notes/folder',
                          queryParameters: {'path': path, 'name': name},
                        ).toString());
                      } else {
                        _openFile(entry);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconForEntry(entry),
                            color: _iconColorForEntry(entry),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (!isFolder && size > 0)
                                  Text(
                                    _formatSize(size),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isOpening)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (isFolder)
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
