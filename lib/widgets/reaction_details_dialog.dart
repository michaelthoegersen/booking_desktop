import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shows a dialog listing who reacted with each emoji.
/// Used by DM chat, group chat, and tour messages.
Future<void> showReactionDetailsDialog(
  BuildContext context,
  List<Map<String, dynamic>> reactions,
) async {
  if (reactions.isEmpty) return;

  // Group by emoji
  final Map<String, List<String>> emojiUsers = {};
  for (final r in reactions) {
    final emoji = r['emoji'] as String? ?? '';
    final userId = r['user_id'] as String? ?? '';
    if (emoji.isEmpty || userId.isEmpty) continue;
    emojiUsers.putIfAbsent(emoji, () => []).add(userId);
  }

  final allUserIds = emojiUsers.values.expand((ids) => ids).toSet().toList();
  if (allUserIds.isEmpty) return;

  // Fetch names
  final sb = Supabase.instance.client;
  Map<String, String> nameMap = {};
  try {
    final rows = await sb
        .from('profiles')
        .select('id, name')
        .inFilter('id', allUserIds);
    for (final row in rows) {
      final id = row['id'] as String? ?? '';
      final name = (row['name'] as String? ?? '').trim();
      if (id.isNotEmpty) {
        nameMap[id] = name.isNotEmpty ? name : 'Ukjent';
      }
    }
  } catch (e) {
    debugPrint('Fetch reaction profiles error: $e');
  }

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reaksjoner'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: emojiUsers.entries.map((entry) {
            final emoji = entry.key;
            final userIds = entry.value;
            final names = userIds
                .map((id) => nameMap[id] ?? id.substring(0, 8))
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: names
                          .map((name) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(name,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Lukk'),
        ),
      ],
    ),
  );
}
