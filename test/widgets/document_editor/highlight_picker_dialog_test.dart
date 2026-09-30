import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/highlight_picker_dialog.dart';

/// #2603: the swatches were bare colored circles, so a screen reader could
/// not tell one highlight from another.
void main() {
  Future<void> pumpDialog(WidgetTester tester, List<Color?> popped) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<Color>(
                context: context,
                builder: (_) => const HighlightPickerDialog(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names every swatch after its color', (tester) async {
    await pumpDialog(tester, []);

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final name in ['Yellow', 'Green', 'Blue', 'Pink', 'Lavender']) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('highlight_swatch_yellow')),
      ),
      isSemantics(tooltip: 'Yellow', isButton: true, hasTapAction: true),
    );
  });

  testWidgets('pops the color of the swatch that was tapped', (tester) async {
    final popped = <Color?>[];
    await pumpDialog(tester, popped);

    await tester.tap(find.byKey(const ValueKey('highlight_swatch_green')));
    await tester.pumpAndSettle();

    expect(popped, [const Color(0xFF8BC34A)]);
  });
}
