import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_columns_button.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/text_scale.dart' show narrowViewport, wideViewport;

/// #1566: the wide bar's Columns button opens a checkbox per optional column
/// of the list view.
void main() {
  Future<List<(FileListColumn, bool)>> pump(
    WidgetTester tester,
    Size size, {
    bool enabled = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final toggles = <(FileListColumn, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FileTopBarColumnsButton(
              columns: const {FileListColumn.modified, FileListColumn.size},
              onColumnToggled: enabled
                  ? (column, visible) => toggles.add((column, visible))
                  : null,
            ),
          ),
        ),
      ),
    );
    return toggles;
  }

  // CheckboxMenuButton hands its key on to the MenuItemButton it builds, so
  // the key names both; they are the same tap target.
  Finder box(FileListColumn column) => find.byWidgetPredicate(
    (widget) =>
        widget is CheckboxMenuButton &&
        widget.key == ValueKey('file_top_bar_column_${column.name}'),
  );

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('checks the shown columns and reports a toggle ($label)', (
      tester,
    ) async {
      final toggles = await pump(tester, size);
      expect(box(FileListColumn.kind), findsNothing);

      await tester.tap(find.byKey(const ValueKey('file_top_bar_columns')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final column in FileListColumn.values) {
        expect(
          tester.widget<CheckboxMenuButton>(box(column)).value,
          column == FileListColumn.modified || column == FileListColumn.size,
          reason: column.name,
        );
        expect(
          find.descendant(of: box(column), matching: find.text(column.label)),
          findsOneWidget,
        );
      }

      await tester.tap(box(FileListColumn.kind));
      await tester.pumpAndSettle();
      await tester.tap(box(FileListColumn.size));
      await tester.pumpAndSettle();

      // The menu stays open, so several columns change in one visit.
      expect(toggles, [
        (FileListColumn.kind, true),
        (FileListColumn.size, false),
      ]);
      expect(box(FileListColumn.kind), findsOneWidget);
    });
  }

  testWidgets('with nothing to call, the button is disabled', (tester) async {
    await pump(tester, wideViewport, enabled: false);

    await tester.tap(
      find.byKey(const ValueKey('file_top_bar_columns')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(box(FileListColumn.kind), findsNothing);
  });

  // Columns belong to a list. Per device the listing is a list whatever the
  // layout switch says, so only the unified grid has none to choose.
  for (final (isGridView, isUnifiedView, live) in const [
    (false, true, true),
    (false, false, true),
    (true, false, true),
    (true, true, false),
  ]) {
    testWidgets('in the bar, grid $isGridView and unified $isUnifiedView '
        'leaves the picker ${live ? 'live' : 'disabled'}', (tester) async {
      tester.view.physicalSize = wideViewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: FileTopBar(
              currentPath: '/docs',
              rootPath: '',
              isGridView: isGridView,
              isUnifiedView: isUnifiedView,
              onToggleUnifiedView: () {},
              isSearchMode: false,
              isUploading: false,
              isCreatingFolder: false,
              isRefreshing: false,
              onGoHome: () {},
              onGoUp: () {},
              onToggleView: () {},
              onSearchChanged: (_) {},
              onSearchClosed: () {},
              onRefresh: () {},
              onUploadPressed: () {},
              onCreateFolderPressed: () {},
              onNewFilePressed: () {},
              columns: const {FileListColumn.size},
              onColumnToggled: (_, _) {},
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('file_top_bar_columns')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(box(FileListColumn.kind), live ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('the view chips carry it beside the layout and grouping', (
    tester,
  ) async {
    tester.view.physicalSize = wideViewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTopBarViewChips(
            isGridView: false,
            isUnifiedView: true,
            onToggleView: () {},
            onToggleUnifiedView: () {},
            columns: const {FileListColumn.kind},
            onColumnToggled: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('file_top_bar_columns')), findsOneWidget);
    expect(find.byTooltip('Columns'), findsOneWidget);
    expect(find.byType(QuarkBarSegmentedToggle), findsOneWidget);
  });
}
