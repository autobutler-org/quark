import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';

/// #2057: Files has had multi-select and batch delete since #986, entered by
/// long-pressing a row. A mouse does not long-press, so on the web the whole
/// feature was invisible and Files looked like it had no bulk actions at all.
/// The toolbar now offers the same entry point a pointer can reach.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    VoidCallback? onStartSelection,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FileTopBar(
            currentPath: '/docs',
            rootPath: '',
            isGridView: false,
            isUnifiedView: false,
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
            onStartSelection: onStartSelection,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the toolbar can start a selection', (tester) async {
    var starts = 0;
    await pumpBar(tester, onStartSelection: () => starts++);

    final select = find.byKey(const ValueKey('file_top_bar_select'));
    expect(select, findsOneWidget);
    expect(find.byTooltip('Select'), findsOneWidget);

    await tester.tap(select);
    await tester.pump();

    expect(starts, 1);
  });

  testWidgets('nothing is offered where selecting makes no sense', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.byKey(const ValueKey('file_top_bar_select')), findsNothing);
  });
}
