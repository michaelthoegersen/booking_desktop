import 'package:flutter/material.dart';

/// Parse message text and highlight @mentions with bold + blue.
List<TextSpan> buildMentionSpans(String text, TextStyle baseStyle) {
  final mentionRegex = RegExp(r'@[\w\u00C0-\u024F]+');
  final spans = <TextSpan>[];
  int lastEnd = 0;
  for (final match in mentionRegex.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    spans.add(TextSpan(
      text: match.group(0),
      style: baseStyle.copyWith(
        fontWeight: FontWeight.w700,
        color: Colors.blue,
      ),
    ));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }
  return spans;
}

/// A participant that can be mentioned.
class MentionCandidate {
  final String id;
  final String name;
  const MentionCandidate({required this.id, required this.name});
}

/// Overlay widget that shows mention suggestions above the text field.
class MentionOverlay extends StatelessWidget {
  final List<MentionCandidate> suggestions;
  final void Function(MentionCandidate) onSelect;

  const MentionOverlay({
    super.key,
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final c = suggestions[index];
          return InkWell(
            onTap: () => onSelect(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(c.name, style: const TextStyle(fontSize: 14)),
            ),
          );
        },
      ),
    );
  }
}

/// Mixin that manages mention state for any chat input.
mixin MentionMixin<T extends StatefulWidget> on State<T> {
  final List<String> mentionedUserIds = [];
  List<MentionCandidate> mentionSuggestions = [];
  List<MentionCandidate> _allCandidates = [];

  static const _allId = '__all__';

  void initMentionCandidates(List<MentionCandidate> candidates) {
    _allCandidates = [
      const MentionCandidate(id: _allId, name: 'alle'),
      ...candidates,
    ];
  }

  /// Call this from the TextEditingController listener.
  void onMentionTextChanged(TextEditingController controller) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (mentionSuggestions.isNotEmpty) {
        setState(() => mentionSuggestions = []);
      }
      return;
    }

    final cursor = sel.baseOffset;
    // Find the last '@' before cursor
    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');

    if (atIndex == -1 ||
        (atIndex > 0 && beforeCursor[atIndex - 1] != ' ' && beforeCursor[atIndex - 1] != '\n')) {
      if (mentionSuggestions.isNotEmpty) {
        setState(() => mentionSuggestions = []);
      }
      return;
    }

    final query = beforeCursor.substring(atIndex + 1).toLowerCase();
    // If there's a space after the query started, close suggestions
    if (query.contains(' ') || query.contains('\n')) {
      if (mentionSuggestions.isNotEmpty) {
        setState(() => mentionSuggestions = []);
      }
      return;
    }

    final filtered = _allCandidates
        .where((c) => c.name.toLowerCase().startsWith(query))
        .toList();
    setState(() => mentionSuggestions = filtered);
  }

  /// Insert the selected mention into the text field.
  void insertMention(
      TextEditingController controller, MentionCandidate candidate) {
    final text = controller.text;
    final sel = controller.selection;
    final cursor = sel.baseOffset;
    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');

    final newText =
        '${text.substring(0, atIndex)}@${candidate.name} ${text.substring(cursor)}';
    controller.text = newText;
    final newCursor = atIndex + candidate.name.length + 2; // @Name + space
    controller.selection = TextSelection.collapsed(offset: newCursor);

    if (candidate.id == _allId) {
      for (final c in _allCandidates) {
        if (c.id != _allId && !mentionedUserIds.contains(c.id)) {
          mentionedUserIds.add(c.id);
        }
      }
    } else if (!mentionedUserIds.contains(candidate.id)) {
      mentionedUserIds.add(candidate.id);
    }
    setState(() => mentionSuggestions = []);
  }

  /// Call after sending message to reset mention state.
  void clearMentions() {
    mentionedUserIds.clear();
    mentionSuggestions = [];
  }
}
