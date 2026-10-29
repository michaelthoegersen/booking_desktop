import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tourflow/widgets/resizable_text_field.dart';

/// Height of the box as laid out, which is what the user actually sees.
double heightOf(WidgetTester tester) =>
    tester.getSize(find.byType(TextField)).height;

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, child: child),
        ),
      ),
    );

void main() {
  testWidgets('grows with the text up to the cap, then stops', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(host(ResizableTextField(
      controller: ctrl,
      minLines: 2,
      maxAutoLines: 5,
    )));

    final start = heightOf(tester);

    await tester.enterText(find.byType(TextField), 'a\nb\nc\nd');
    await tester.pump();
    final grown = heightOf(tester);
    expect(grown, greaterThan(start), reason: 'four lines must be taller than two');

    await tester.enterText(find.byType(TextField), 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj');
    await tester.pump();
    final capped = heightOf(tester);
    expect(capped, greaterThan(grown), reason: 'ten lines fill the five-line cap');

    await tester.enterText(find.byType(TextField), List.filled(40, 'x').join('\n'));
    await tester.pump();
    expect(heightOf(tester), capped,
        reason: 'past maxAutoLines the box scrolls instead of growing');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the grip drags the box taller and shorter', (tester) async {
    await tester.pumpWidget(host(ResizableTextField(
      controller: TextEditingController(),
      minLines: 3,
    )));

    final start = heightOf(tester);
    final grip = tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8);

    await tester.dragFrom(grip, const Offset(0, 140));
    await tester.pump();
    final taller = heightOf(tester);
    expect(taller, closeTo(start + 140, 1.0),
        reason: 'the box should follow the pointer one-to-one');

    await tester.dragFrom(
        tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8),
        const Offset(0, -100));
    await tester.pump();
    expect(heightOf(tester), closeTo(taller - 100, 1.0));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a dragged box stops growing with the text', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(host(ResizableTextField(
      controller: ctrl,
      minLines: 2,
      maxAutoLines: 20,
    )));

    final grip = tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8);
    await tester.dragFrom(grip, const Offset(0, 60));
    await tester.pump();
    final fixed = heightOf(tester);

    await tester.enterText(find.byType(TextField), List.filled(30, 'x').join('\n'));
    await tester.pump();
    expect(heightOf(tester), fixed,
        reason: 'a box the user sized must stay that size');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('double-click on the grip hands the height back', (tester) async {
    await tester.pumpWidget(host(ResizableTextField(
      controller: TextEditingController(),
      minLines: 3,
    )));

    final start = heightOf(tester);
    await tester.dragFrom(
        tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8),
        const Offset(0, 120));
    await tester.pump();
    expect(heightOf(tester), isNot(start));

    final grip = tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8);
    await tester.tapAt(grip);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(grip);
    await tester.pumpAndSettle();
    expect(heightOf(tester), start);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('cannot be dragged below minHeight', (tester) async {
    await tester.pumpWidget(host(ResizableTextField(
      controller: TextEditingController(),
      minLines: 3,
      minHeight: 64,
    )));

    await tester.dragFrom(
        tester.getBottomRight(find.byType(TextField)) - const Offset(8, 8),
        const Offset(0, -500));
    await tester.pump();
    expect(heightOf(tester), 64);
    await tester.pump(const Duration(seconds: 2));
  });
}
