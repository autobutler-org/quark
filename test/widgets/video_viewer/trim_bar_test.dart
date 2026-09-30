import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/video_viewer/trim_bar.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2604: the trim handles moved only under a dragging pointer, so a keyboard
/// user could not trim a video at all.
void main() {
  Future<List<String>> pumpBar(WidgetTester tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: TrimBar(
                start: 0.2,
                end: 0.8,
                duration: const Duration(seconds: 100),
                onStartChanged: (v) =>
                    events.add('start:${v.toStringAsFixed(2)}'),
                onEndChanged: (v) => events.add('end:${v.toStringAsFixed(2)}'),
              ),
            ),
          ),
        ),
      ),
    );
    return events;
  }

  int ringsShown(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(QuarkFocusRing),
          matching: find.byType(DecoratedBox),
        ),
      )
      .where((box) => (box.decoration as BoxDecoration).border != null)
      .length;

  testWidgets('the arrow keys nudge the focused handle', (tester) async {
    final events = await pumpBar(tester);
    expect(ringsShown(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringsShown(tester), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

    expect(events, ['start:0.21', 'end:0.79']);
  });

  testWidgets('each handle is a named slider', (tester) async {
    await pumpBar(tester);

    expect(find.bySemanticsLabel('Trim start'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Trim end')),
      isSemantics(
        label: 'Trim end',
        value: '01:20.0',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
  });
}
