import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// A multi-line text field that behaves like a browser `<textarea>`: it grows
/// by itself as you type, and the grip in the bottom-right corner can be
/// dragged to make the box as tall as you like. Double-click (or double-tap)
/// the grip to hand the height back to the field.
///
/// The two modes are deliberately separate render paths so Flutter does the
/// measuring in both cases:
///
///  * automatic — `minLines`/`maxAutoLines` on the field itself, so the box
///    stretches with the content up to the cap and then scrolls internally.
///  * dragged — an explicit height with `expands: true`, so a box the user has
///    sized stays exactly that size no matter how much is typed into it.
class ResizableTextField extends StatefulWidget {
  const ResizableTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.minLines = 3,
    this.maxAutoLines = 20,
    this.initialHeight,
    this.minHeight = 64,
    this.maxHeight = 1600,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;

  /// Height the box starts at, in lines, while it manages its own height.
  final int minLines;

  /// The box stops growing on its own here and scrolls instead. Drag the grip
  /// to go past it.
  final int maxAutoLines;

  /// Start out at a fixed pixel height instead of an automatic one. Use this
  /// where the field replaces a hard-coded `SizedBox` height.
  final double? initialHeight;

  final double minHeight;
  final double maxHeight;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<ResizableTextField> createState() => _ResizableTextFieldState();
}

class _ResizableTextFieldState extends State<ResizableTextField> {
  /// null = the field decides its own height.
  double? _height;
  final _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _height = widget.initialHeight;
  }

  /// Picks up the height the box happens to have right now, so the first drag
  /// continues from what is on screen instead of jumping to a default.
  void _beginDrag() {
    if (_height != null) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    _height = (box?.size.height ?? widget.minHeight)
        .clamp(widget.minHeight, widget.maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    final auto = _height == null;

    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      style: widget.style,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      minLines: auto ? widget.minLines : null,
      maxLines: auto ? widget.maxAutoLines : null,
      expands: !auto,
    );

    return Stack(
      children: [
        auto ? field : SizedBox(height: _height, child: field),
        Positioned(right: 0, bottom: 0, child: _grip(context)),
      ],
    );
  }

  Widget _grip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Report from where the pointer went down, not from where the drag was
        // recognised, or the box lags the grip by the slop distance (~20px)
        // and never catches up.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => setState(_beginDrag),
        onPanUpdate: (d) => setState(() {
          _height = ((_height ?? widget.minHeight) + d.delta.dy)
              .clamp(widget.minHeight, widget.maxHeight);
        }),
        onDoubleTap: () => setState(() => _height = null),
        child: Tooltip(
          message: 'Dra for å endre høyden · dobbeltklikk for automatisk',
          waitDuration: const Duration(milliseconds: 600),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Padding(
              padding: const EdgeInsets.only(right: 5, bottom: 5),
              child: Align(
                alignment: Alignment.bottomRight,
                child: CustomPaint(
                  size: const Size(10, 10),
                  painter: _GripPainter(
                      cs.onSurfaceVariant.withValues(alpha: 0.55)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two short diagonals of a resize grip.
class _GripPainter extends CustomPainter {
  const _GripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(size.width, size.height * 0.35), Offset(size.width * 0.35, size.height), p);
    canvas.drawLine(
        Offset(size.width, size.height * 0.8), Offset(size.width * 0.8, size.height), p);
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}
