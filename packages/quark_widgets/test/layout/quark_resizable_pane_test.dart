// The sidebar pane every wide layout resizes and collapses through (#4294).
//
// The pane holds no width or collapsed state of its own, so every case drives
// it the way a page does: a StatefulBuilder holds the two values and the
// callbacks write them back.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _handle = ValueKey('resizable_pane_handle_albums');
const _pane = ValueKey('resizable_pane_albums');

/// A start-edge pane beside an expanded content area, with its state held in
/// a StatefulBuilder and every change recorded in [events].
Widget buildPane({
  required List<String> events,
  double width = 280,
  bool collapsed = false,
  QuarkPaneEdge edge = QuarkPaneEdge.start,
}) {
  var current = width;
  var isCollapsed = collapsed;
  return StatefulBuilder(
    builder: (context, setState) {
      final pane = QuarkResizablePane(
        id: 'albums',
        semanticLabel: 'Resize albums',
        edge: edge,
        width: current,
        defaultWidth: 280,
        isCollapsed: isCollapsed,
        onWidthChanged: (w) => setState(() {
          events.add('width ${w.round()}');
          current = w;
        }),
        onCollapsedChanged: (c) => setState(() {
          events.add(c ? 'collapse' : 'expand');
          isCollapsed = c;
        }),
        child: const ColoredBox(color: Colors.transparent),
      );
      const content = Expanded(child: Text('content'));
      return Row(
        children: edge == QuarkPaneEdge.start
            ? [pane, content]
            : [content, pane],
      );
    },
  );
}

double paneWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(_pane)).width;

void main() {
  testBothViewports('lays out the pane and its handle', (tester, size) async {
    await pumpAt(tester, buildPane(events: []), size: size);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_handle), findsOneWidget);
    expect(
      tester.getSize(find.byKey(_handle)).width,
      QuarkResizablePane.handleWidth,
    );
  });

  testWidgets('dragging the handle resizes the pane', (tester) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events));
    expect(paneWidth(tester), 280);

    await tester.drag(find.byKey(_handle), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(paneWidth(tester), closeTo(340, 1));
    expect(events.last, 'width 340');
  });

  testWidgets('an end-edge pane grows when dragged toward the start', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events, edge: QuarkPaneEdge.end));

    await tester.drag(find.byKey(_handle), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(paneWidth(tester), closeTo(340, 1));
  });

  testWidgets('the width stops at the max and at half the window', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events));

    await tester.drag(find.byKey(_handle), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(paneWidth(tester), QuarkResizablePane.defaultMaxWidth);

    expect(
      QuarkResizablePane.widthIn(
        tester.element(find.byKey(_handle)),
        width: 900,
      ),
      QuarkResizablePane.defaultMaxWidth,
    );
  });

  testWidgets('the width never leaves the content less than half the window', (
    tester,
  ) async {
    await pumpAt(tester, buildPane(events: []), size: const Size(900, 600));
    expect(
      QuarkResizablePane.widthIn(
        tester.element(find.byKey(_handle)),
        width: 480,
      ),
      450,
    );
  });

  testWidgets('dragging below the min width collapses the pane', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events));

    await tester.drag(find.byKey(_handle), const Offset(-250, 0));
    await tester.pumpAndSettle();

    expect(events, contains('collapse'));
    expect(paneWidth(tester), 0);
    expect(find.byKey(_handle), findsOneWidget);
  });

  testWidgets('dragging a collapsed pane back out reopens it', (tester) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events, collapsed: true));

    await tester.drag(find.byKey(_handle), const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(events.first, 'expand');
    expect(paneWidth(tester), closeTo(240, 1));
  });

  testWidgets('arrow keys resize and Enter toggles collapse', (tester) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events));

    Focus.of(tester.element(find.byKey(_handle))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(paneWidth(tester), 280 + QuarkResizablePane.keyboardStep);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(paneWidth(tester), 280);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(paneWidth(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(paneWidth(tester), 280);
    expect(events.where((e) => !e.startsWith('width')), ['collapse', 'expand']);
  });

  testWidgets('double-tapping the handle resets the default width', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, buildPane(events: events, width: 400));
    expect(paneWidth(tester), 400);

    await tester.tap(find.byKey(_handle));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(_handle));
    await tester.pumpAndSettle();

    expect(paneWidth(tester), 280);
    expect(events, ['width 280']);
  });

  testWidgets('the handle names itself and offers a resize cursor', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, buildPane(events: []));

    expect(find.bySemanticsLabel('Resize albums'), findsOneWidget);
    final cursor = tester.widget<MouseRegion>(
      find
          .ancestor(of: find.byKey(_handle), matching: find.byType(MouseRegion))
          .first,
    );
    expect(cursor.cursor, SystemMouseCursors.resizeColumn);
    semantics.dispose();
  });

  testWidgets('collapsing animates, and jumps under reduced motion', (
    tester,
  ) async {
    await pumpAt(tester, buildPane(events: []));
    Focus.of(tester.element(find.byKey(_handle))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paneWidth(tester), inExclusiveRange(0, 280));
    await tester.pumpAndSettle();

    await pumpAt(
      tester,
      MediaQuery(
        data: const MediaQueryData(size: wideViewport, disableAnimations: true),
        child: buildPane(events: []),
      ),
    );
    Focus.of(tester.element(find.byKey(_handle))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(paneWidth(tester), 0);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the handle line comes from the tokens', (
      tester,
    ) async {
      await pumpAt(tester, buildPane(events: []), brightness: brightness);
      final line = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('resizable_pane_line_albums')),
      );
      expect(line.color, tokens.border);
    });
  }
}
