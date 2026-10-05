import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_editor_toolbar.dart';

// flutter_quill's toolbar draws increase indent before decrease. Every other
// document editor reads the pair left to right as less indent, then more
// (#2463).
void main() {
  late QuillController controller;

  setUp(() => controller = QuillController.basic());
  tearDown(() => controller.dispose());

  const decrease = ValueKey('document_editor_indent_decrease');
  const increase = ValueKey('document_editor_indent_increase');

  Future<void> pumpToolbar(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(
          // In a Column, as the editor body places it.
          body: Column(
            children: [
              DocumentEditorToolbar(
                controller: controller,
                onPickBackgroundColor: (_, _) async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The attributes on the document's first line.
  Map<String, dynamic> lineAttributes() {
    for (final op in controller.document.toDelta().toJson()) {
      if (op['insert'] == '\n') {
        return (op['attributes'] as Map<String, dynamic>?) ?? {};
      }
    }
    return {};
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('decrease indent sits before increase on a $name viewport', (
      WidgetTester tester,
    ) async {
      await pumpToolbar(tester, size);

      expect(find.byKey(decrease), findsOneWidget);
      expect(find.byKey(increase), findsOneWidget);
      final less = tester.getCenter(find.byKey(decrease));
      final more = tester.getCenter(find.byKey(increase));
      // Same row, decrease first.
      if (less.dy == more.dy) {
        expect(less.dx, lessThan(more.dx));
      } else {
        expect(less.dy, lessThan(more.dy));
      }
    });
  }

  // A phone used to wrap the toolbar onto three rows, taking the space the
  // document needs. It scrolls sideways instead (#2770).
  testWidgets('is one row high on a narrow viewport', (
    WidgetTester tester,
  ) async {
    await pumpToolbar(tester, const Size(1280, 800));
    final oneRow = tester.getSize(find.byType(DocumentEditorToolbar)).height;

    await pumpToolbar(tester, const Size(360, 640));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DocumentEditorToolbar)).height, oneRow);
  });

  testWidgets('each button shows its own glyph and tooltip', (
    WidgetTester tester,
  ) async {
    await pumpToolbar(tester, const Size(1280, 800));

    expect(
      find.descendant(
        of: find.byKey(decrease),
        matching: find.byIcon(Icons.format_indent_decrease),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(increase),
        matching: find.byIcon(Icons.format_indent_increase),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Decrease indent'), findsOneWidget);
    expect(find.byTooltip('Increase indent'), findsOneWidget);
  });

  testWidgets('each button still acts on the selection', (
    WidgetTester tester,
  ) async {
    await pumpToolbar(tester, const Size(1280, 800));

    await tester.tap(find.byKey(increase));
    await tester.pump();
    await tester.tap(find.byKey(increase));
    await tester.pump();
    expect(lineAttributes(), containsPair('indent', 2));

    await tester.tap(find.byKey(decrease));
    await tester.pump();
    expect(lineAttributes(), containsPair('indent', 1));
  });
}
