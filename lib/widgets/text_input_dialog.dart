import 'package:flutter/material.dart';

import 'resizable_text_field.dart';

/// A text dialog that owns its own [TextEditingController].
///
/// The pattern this replaces — creating the controller at the call site and
/// disposing it on the line after `await showDialog(...)` — tears the
/// controller down while the dialog route is still animating out, which trips
/// `'_dependents.isEmpty': is not true` on a red screen. Creating it inside
/// `showDialog`'s `builder` is no better: the builder runs again on rebuilds,
/// so whatever the user typed is replaced by a fresh, empty controller.
///
/// Returns the text on save, or null if the dialog was cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? label,
  String? description,
  bool multiline = false,
  bool? trim,
  TextInputType? keyboardType,
  double width = 450,
  double initialHeight = 220,
  String confirmLabel = 'Lagre',
  String cancelLabel = 'Avbryt',
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initial: initial,
      hint: hint,
      label: label,
      description: description,
      multiline: multiline,
      trim: trim ?? !multiline,
      keyboardType: keyboardType,
      width: width,
      initialHeight: initialHeight,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.label,
    required this.description,
    required this.multiline,
    required this.trim,
    required this.keyboardType,
    required this.width,
    required this.initialHeight,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? label;
  final String? description;
  final bool multiline;
  final bool trim;
  final TextInputType? keyboardType;
  final double width;
  final double initialHeight;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, widget.trim ? _ctrl.text.trim() : _ctrl.text);

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: widget.hint,
      labelText: widget.label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

    final field = widget.multiline
        ? ResizableTextField(
            controller: _ctrl,
            autofocus: true,
            initialHeight: widget.initialHeight,
            decoration: decoration,
          )
        : TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: widget.keyboardType,
            decoration: decoration,
            onSubmitted: (_) => _submit(),
          );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description != null) ...[
              Text(widget.description!, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
            ],
            field,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: Colors.red)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
