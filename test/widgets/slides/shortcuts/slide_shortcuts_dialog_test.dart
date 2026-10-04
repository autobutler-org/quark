import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/shortcuts/slide_shortcuts_dialog.dart';
import 'package:quark/widgets/slides/shortcuts/slide_shortcuts_help.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The keyboard shortcuts dialog and the `?` / F1 binding that opens it
/// (#1168).
void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.linux,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(
          themeColor: QuarkThemeColor.classic,
        ).copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: SlideShortcutsDialog()),
      ),
    );
    await tester.pump();
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('lists every section and fits ($name, 2.0 text)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pumpDialog(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('slide_shortcut_section_editing')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('slide_shortcuts_close'))),
        greaterThanOrEqualTo(const Size(48, 48)),
      );
    });

    testWidgets('close and search meet tap guidelines ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpDialog(tester);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('keys read Ctrl elsewhere and Cmd on a Mac', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpDialog(tester);
    final undo = find.byKey(const ValueKey('slide_shortcut_undo'));
    expect(
      find.descendant(of: undo, matching: find.text('Ctrl')),
      findsOneWidget,
    );
    await pumpDialog(tester, platform: TargetPlatform.macOS);
    await tester.pumpAndSettle();
    expect(find.descendant(of: undo, matching: find.text('⌘')), findsOneWidget);
    expect(find.text('Ctrl'), findsNothing);
  });

  testWidgets('a row reads as one labeled stop', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final handle = tester.ensureSemantics();
    await pumpDialog(tester);
    expect(
      find.bySemanticsLabel('Redo, Control Shift Z or Control Y'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('search filters sections and shows an empty state', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpDialog(tester);
    final search = find.byKey(const ValueKey('slide_shortcuts_search'));
    await tester.enterText(search, 'bold');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('slide_shortcut_text_bold')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('slide_shortcut_undo')), findsNothing);
    expect(
      find.byKey(const ValueKey('slide_shortcut_section_present')),
      findsNothing,
    );

    await tester.enterText(search, 'nothing like this');
    await tester.pump();
    expect(find.byKey(const ValueKey('slide_shortcuts_empty')), findsOneWidget);

    await tester.enterText(search, '');
    await tester.pump();
    expect(find.byKey(const ValueKey('slide_shortcut_undo')), findsOneWidget);
  });

  group('SlideShortcutsHelp', () {
    Future<void> pumpHelp(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SlideShortcutsHelp(
              child: Column(
                children: [
                  Focus(
                    autofocus: true,
                    child: const SizedBox(width: 50, height: 50),
                  ),
                  const SizedBox(width: 200, child: TextField()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final dialog = find.byKey(const ValueKey('slide_shortcuts_dialog'));

    testWidgets('? opens the dialog and Close dismisses it', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpHelp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('slide_shortcuts_close')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('F1 opens the dialog', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpHelp(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
    });

    testWidgets('? is left to a focused text field', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpHelp(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });
  });
}
