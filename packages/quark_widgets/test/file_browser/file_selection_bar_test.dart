import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The selection bar is custom chrome, not a real AppBar, so nothing pads it
/// away from the status bar for free. On a notched iPhone it drew underneath
/// the clock and the wifi/battery indicators, burying "Deselect all" (#1597).
///
/// These pump the bar under a MediaQuery carrying real device insets and check
/// where the controls actually land, which is the part a screenshot caught and
/// a widget test can keep caught. They moved here with the widget.
void main() {
  // iPhone 15 Pro portrait: 59pt status bar / Dynamic Island band.
  const notchInsets = EdgeInsets.only(top: 59, bottom: 34);
  // Same device rotated: the inset moves to the sides.
  const landscapeInsets = EdgeInsets.only(left: 59, right: 59, bottom: 21);

  Future<void> pumpSelectionBar(
    WidgetTester tester, {
    Size size = narrowViewport,
    EdgeInsets insets = EdgeInsets.zero,
    int selectedCount = 3,
    int totalCount = 3,
    bool canDelete = true,
    bool canRestore = false,
    void Function(String event)? log,
  }) {
    void record(String event) => log?.call(event);
    return pumpAt(
      tester,
      MediaQuery(
        data: MediaQueryData(padding: insets, viewPadding: insets),
        child: Column(
          children: [
            FileSelectionBar(
              selectedCount: selectedCount,
              totalCount: totalCount,
              onSelectAll: () => record('selectAll'),
              onDeselectAll: () => record('deselectAll'),
              onCancel: () => record('cancel'),
              onDelete: canDelete ? () => record('delete') : null,
              onRestore: canRestore ? () => record('restore') : null,
              deleteTooltip: canRestore
                  ? 'Delete permanently'
                  : 'Delete selected',
            ),
          ],
        ),
      ),
      size: size,
    );
  }

  testBothViewports('keeps every control below the top inset', (
    tester,
    size,
  ) async {
    await pumpSelectionBar(tester, size: size, insets: notchInsets);

    final controls = <String, Finder>{
      'the close button': find.byTooltip('Cancel selection'),
      'the count label': find.text('3 selected'),
      'Deselect all': find.text('Deselect all'),
      'the delete button': find.byTooltip('Delete selected'),
    };
    for (final entry in controls.entries) {
      expect(
        tester.getRect(entry.value).top,
        greaterThanOrEqualTo(notchInsets.top),
        reason: '${entry.key} must clear the status bar',
      );
    }
  });

  testWidgets('paints the bar through the inset region', (tester) async {
    await pumpSelectionBar(tester, insets: notchInsets);

    // The bar itself starts at y=0 — only its contents are pushed down — so
    // the status bar sits on the bar's own surface color, not on whatever is
    // scrolling underneath it.
    expect(tester.getRect(find.byType(FileSelectionBar)).top, 0);
    expect(
      tester.getRect(find.byType(FileSelectionBar)).height,
      56 + notchInsets.top,
    );
  });

  testWidgets('honors the side insets in landscape', (tester) async {
    await pumpSelectionBar(tester, size: wideViewport, insets: landscapeInsets);

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byTooltip('Cancel selection')).left,
      greaterThanOrEqualTo(landscapeInsets.left),
    );
    expect(
      tester.getRect(find.byTooltip('Delete selected')).right,
      lessThanOrEqualTo(screenWidth - landscapeInsets.right),
    );
  });

  testWidgets('adds no padding on a device without insets', (tester) async {
    await pumpSelectionBar(tester);

    expect(tester.getRect(find.byType(FileSelectionBar)).height, 56);
  });

  testBothViewports('offers "Select all" until everything is selected', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpSelectionBar(
      tester,
      size: size,
      selectedCount: 1,
      totalCount: 3,
      log: events.add,
    );

    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Deselect all'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file_selection_toggle_all')));
    await tester.pump();

    expect(events, ['selectAll']);
  });

  testBothViewports('emits every action it offers', (tester, size) async {
    final events = <String>[];
    await pumpSelectionBar(tester, size: size, log: events.add);

    await tester.tap(find.byKey(const ValueKey('file_selection_toggle_all')));
    await tester.tap(find.byKey(const ValueKey('file_selection_delete')));
    await tester.tap(find.byKey(const ValueKey('file_selection_cancel')));
    await tester.pump();

    expect(events, ['deselectAll', 'delete', 'cancel']);
  });

  testWidgets('dims the delete button when deleting is not offered', (
    tester,
  ) async {
    await pumpSelectionBar(tester, canDelete: false);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('file_selection_delete')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('leaves restore out unless it is offered', (tester) async {
    await pumpSelectionBar(tester);

    expect(find.byKey(const ValueKey('file_selection_restore')), findsNothing);
  });

  testBothViewports('offers restore and a permanent delete in the trash', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpSelectionBar(
      tester,
      size: size,
      insets: notchInsets,
      canRestore: true,
      log: events.add,
    );

    expect(find.byTooltip('Delete permanently'), findsOneWidget);
    expect(find.byTooltip('Delete selected'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file_selection_restore')));
    await tester.tap(find.byKey(const ValueKey('file_selection_delete')));
    await tester.pump();

    expect(events, ['restore', 'delete']);
  });
}
