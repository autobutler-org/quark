import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_editor_toolbar.dart';
import 'package:quark_widgets/quark_widgets.dart';

// flutter_quill's toolbar draws increase indent before decrease. Every other
// document editor reads the pair left to right as less indent, then more
// (#2463).
void main() {
  late QuillController controller;

  setUp(() => controller = QuillController.basic());
  tearDown(() => controller.dispose());

  const decrease = ValueKey('document_editor_indent_decrease');
  const increase = ValueKey('document_editor_indent_increase');

  Future<void> pumpToolbar(
    WidgetTester tester,
    Size size, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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

  // The toolbar is filled with the scheme's surfaceContainer, which
  // QuarkTheme left to Material's seed-derived tonal palette, so under a
  // theme color it matched none of the chrome around it (#2786).
  for (final themeColor in [
    QuarkThemeColor.classic,
    QuarkThemeColor.pink,
    QuarkThemeColor.lime,
  ]) {
    for (final brightness in Brightness.values) {
      final id = '${themeColor.storageValue} in ${brightness.name}';
      testWidgets('$id: the fill is the theme\'s chrome', (
        WidgetTester tester,
      ) async {
        final tokens = themeColor.tokensFor(brightness);
        await pumpToolbar(
          tester,
          const Size(1280, 800),
          theme: brightness == Brightness.dark
              ? QuarkTheme.dark(themeColor: themeColor)
              : QuarkTheme.light(themeColor: themeColor),
        );

        final fill = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(DocumentEditorToolbar),
                matching: find.byType(Container),
              ),
            )
            .first;
        final color = (fill.decoration! as BoxDecoration).color;
        expect(color, tokens.chrome);
        expect(
          color,
          Theme.of(
            tester.element(find.byType(Scaffold)),
          ).colorScheme.surfaceContainer,
        );
      });
    }
  }
}
