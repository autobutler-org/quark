import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';

/// The search field reports the query being typed before the debounced search
/// runs, so the result banner can follow the field (#2098).
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required ValueChanged<String> onSearchChanged,
    ValueChanged<String>? onSearchDraft,
    VoidCallback? onSearchClosed,
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
            onSearchChanged: onSearchChanged,
            onSearchDraft: onSearchDraft,
            onSearchClosed: onSearchClosed ?? () {},
            onRefresh: () {},
            onUploadPressed: () {},
            onCreateFolderPressed: () {},
            onNewFilePressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the draft callback fires before the debounced search', (
    tester,
  ) async {
    final drafts = <String>[];
    final commits = <String>[];
    await pumpBar(
      tester,
      onSearchDraft: drafts.add,
      onSearchChanged: commits.add,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), ' mountain ');

    expect(drafts, ['mountain']);
    expect(commits, isEmpty);

    await tester.pump(const Duration(milliseconds: 349));
    expect(commits, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(commits, ['mountain']);
  });

  testWidgets('clearing the field reports an empty draft and does not search', (
    tester,
  ) async {
    final drafts = <String>[];
    final commits = <String>[];
    var closes = 0;
    await pumpBar(
      tester,
      onSearchDraft: drafts.add,
      onSearchChanged: commits.add,
      onSearchClosed: () => closes++,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'family');
    await tester.pump(const Duration(milliseconds: 350));
    expect(commits, ['family']);

    await tester.enterText(find.byType(TextField), '');

    expect(drafts, ['family', '']);
    expect(closes, 1);
    expect(commits, ['family']);

    await tester.pump(const Duration(milliseconds: 350));
    expect(commits, ['family']);
  });
}
