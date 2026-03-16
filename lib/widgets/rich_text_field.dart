import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A TextField with a formatting toolbar that stores markdown.
/// Toggle between edit mode and preview mode.
class RichTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int minLines;
  final int maxLines;

  const RichTextField({
    super.key,
    required this.controller,
    this.label = '',
    this.minLines = 3,
    this.maxLines = 8,
  });

  @override
  State<RichTextField> createState() => _RichTextFieldState();
}

class _RichTextFieldState extends State<RichTextField> {
  bool _preview = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _wrap(String before, String after) {
    final ctrl = widget.controller;
    final sel = ctrl.selection;
    final text = ctrl.text;

    if (!sel.isValid || sel.isCollapsed) {
      // No selection — insert markers and place cursor between them
      final insert = '$before$after';
      final offset = sel.isValid ? sel.baseOffset : text.length;
      ctrl.text = text.substring(0, offset) + insert + text.substring(offset);
      ctrl.selection = TextSelection.collapsed(offset: offset + before.length);
    } else {
      final selected = text.substring(sel.start, sel.end);
      final replacement = '$before$selected$after';
      ctrl.text = text.substring(0, sel.start) + replacement + text.substring(sel.end);
      ctrl.selection = TextSelection(
        baseOffset: sel.start + before.length,
        extentOffset: sel.start + before.length + selected.length,
      );
    }
    _focusNode.requestFocus();
  }

  void _prefixLine(String prefix) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final offset = sel.isValid ? sel.baseOffset : text.length;

    // Find start of current line
    int lineStart = text.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;

    ctrl.text = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    ctrl.selection = TextSelection.collapsed(offset: offset + prefix.length);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(widget.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),

        // Toolbar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              _toolBtn(Icons.format_bold, 'Fet', () => _wrap('**', '**')),
              _toolBtn(Icons.format_italic, 'Kursiv', () => _wrap('*', '*')),
              _toolBtn(Icons.strikethrough_s, 'Gjennomstreking', () => _wrap('~~', '~~')),
              _divider(),
              _toolBtn(Icons.title, 'Overskrift', () => _prefixLine('## ')),
              _toolBtn(Icons.format_list_bulleted, 'Punktliste', () => _prefixLine('- ')),
              _toolBtn(Icons.format_list_numbered, 'Nummerert', () => _prefixLine('1. ')),
              const Spacer(),
              _toggleBtn(cs),
            ],
          ),
        ),

        // Editor / Preview
        Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.outlineVariant),
              right: BorderSide(color: cs.outlineVariant),
              bottom: BorderSide(color: cs.outlineVariant),
            ),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(10)),
          ),
          child: _preview ? _buildPreview(cs) : _buildEditor(cs),
        ),
      ],
    );
  }

  Widget _buildEditor(ColorScheme cs) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: TextInputType.multiline,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
        hintText: 'Skriv her...',
      ),
    );
  }

  Widget _buildPreview(ColorScheme cs) {
    final text = widget.controller.text;
    if (text.trim().isEmpty) {
      return Container(
        constraints: BoxConstraints(minHeight: widget.minLines * 22.0),
        padding: const EdgeInsets.all(12),
        child: Text('Ingen innhold',
            style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
      );
    }
    return Container(
      constraints: BoxConstraints(minHeight: widget.minLines * 22.0),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(fontSize: 14, color: cs.onSurface),
          h1: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
          h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
          h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
          listBullet: TextStyle(fontSize: 14, color: cs.onSurface),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: _preview ? null : onTap,
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 20,
        child: VerticalDivider(width: 1, thickness: 1),
      ),
    );
  }

  Widget _toggleBtn(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _preview = !_preview),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _preview ? cs.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _preview ? Icons.edit : Icons.visibility,
              size: 15,
              color: _preview ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              _preview ? 'Rediger' : 'Forhåndsvis',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _preview ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only markdown renderer for displaying stored markdown text.
class MarkdownText extends StatelessWidget {
  final String data;
  final double fontSize;

  const MarkdownText(this.data, {super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, color: cs.onSurface),
        h1: TextStyle(fontSize: fontSize + 8, fontWeight: FontWeight.w800, color: cs.onSurface),
        h2: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.w700, color: cs.onSurface),
        h3: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.w600, color: cs.onSurface),
        listBullet: TextStyle(fontSize: fontSize, color: cs.onSurface),
      ),
    );
  }
}
