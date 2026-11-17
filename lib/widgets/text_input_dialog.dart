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
  bool multiline = false,
  double width = 450,
  double initialHeight = 220,
  String confirmLabel = 'Lagre',
  String cancelLabel = 'Avbryt',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initial: initial,
      hint: hint,
      multiline: multiline,
      width: width,
      initialHeight: initialHeight,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.multiline,
    required this.width,
    required this.initialHeight,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String initial;
  final String? hint;
  final bool multiline;
  final double width;
  final double initialHeight;
  final String confirmLabel;
  final String cancelLabel;

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

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: widget.hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.width,
        child: widget.multiline
            ? ResizableTextField(
                controller: _ctrl,
                autofocus: true,
                initialHeight: widget.initialHeight,
                decoration: decoration,
              )
            : TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: decoration,
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, widget.multiline ? _ctrl.text : _ctrl.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
