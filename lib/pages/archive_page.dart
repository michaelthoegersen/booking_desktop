import 'package:flutter/material.dart';
import '../services/offer_storage_service.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _archived = [];

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await OfferStorageService.loadArchivedOffers();
      if (!mounted) return;
      setState(() => _archived = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unarchive(String id, String production) async {
    try {
      await OfferStorageService.unarchiveDraft(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored "$production"')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _permanentlyDelete(String id, String production) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'This will permanently delete:\n\n"$production"\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await OfferStorageService.permanentlyDeleteDraft(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permanently deleted "$production"')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _fmtDate(dynamic value) {
    try {
      if (value == null) return '';
      final d = value is DateTime ? value : DateTime.parse(value.toString());
      return '${d.day.toString().padLeft(2, '0')}.'
          '${d.month.toString().padLeft(2, '0')}.'
          '${d.year}';
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'draft':
        return Colors.purple.shade400;
      case 'inquiry':
        return Colors.orange.shade400;
      case 'confirmed':
        return Colors.green.shade500;
      case 'invoiced':
        return Colors.blue.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = _searchQuery.isEmpty
        ? _archived
        : _archived.where((row) {
            final prod = (row['production'] ?? '').toString().toLowerCase();
            final comp = (row['company'] ?? '').toString().toLowerCase();
            return prod.contains(_searchQuery) || comp.contains(_searchQuery);
          }).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Archive',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),

                const SizedBox(width: 16),

                SizedBox(
                  width: 240,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search archive…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      isDense: true,
                    ),
                  ),
                ),

                const Spacer(),

                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // List
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              const Expanded(
                child: Center(child: Text('No archived offers.')),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final row = filtered[i];
                    final id = row['id']?.toString() ?? '';
                    final production =
                        row['production']?.toString() ?? '—';
                    final company = row['company']?.toString() ?? '';
                    final status = (row['status'] ?? '').toString();
                    final updatedDate =
                        _fmtDate(row['updated_at'] ?? row['created_at']);
                    final updatedBy =
                        row['updated_name']?.toString() ?? 'Unknown';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,

                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            production,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          if (company.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• $company',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          if (status.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(status),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      subtitle: Text(
                        'Updated by: $updatedBy  •  $updatedDate',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),

                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.unarchive_outlined),
                            tooltip: 'Restore',
                            onPressed: id.isEmpty
                                ? null
                                : () => _unarchive(id, production),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_forever_outlined,
                              color: cs.error,
                            ),
                            tooltip: 'Delete permanently',
                            onPressed: id.isEmpty
                                ? null
                                : () => _permanentlyDelete(id, production),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
