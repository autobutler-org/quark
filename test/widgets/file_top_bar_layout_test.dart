import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2311: Files wears the shared QuarkAppBar, with its actions in the package
/// bar buttons, and on a phone its secondary actions collapse into the bar's
/// labeled Views menu instead of a breakpoint of its own.
void main() {
  Future<void> pumpBar(
    WidgetTester tester,
    Size size, {
    bool isSearchMode = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(),
        home: Scaffold(
          appBar: FileTopBar(
            currentPath: '/docs',
            rootPath: '',
            isGridView: false,
            isUnifiedView: false,
            onToggleUnifiedView: () {},
            isSearchMode: isSearchMode,
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
            onStartSelection: () {},
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const narrow = Size(360, 640);
  const wide = Size(1280, 800);

  for (final size in [narrow, wide]) {
    final label = size == narrow ? 'narrow' : 'wide';

    testWidgets('is a QuarkAppBar whose actions are bar buttons ($label)', (
      tester,
    ) async {
      await pumpBar(tester, size);

      expect(find.byType(QuarkAppBar), findsOneWidget);
      for (final key in const [
        'refresh_button',
        'file_top_bar_back',
        'file_top_bar_up',
        'file_top_bar_search',
        'file_top_bar_select',
        'theme_toggle',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IconButton),
          ),
          findsOneWidget,
          reason: key,
        );
        // Search is the row's slack: on a phone it may scale down.
        if (key == 'file_top_bar_search') continue;
        expect(
          tester.getSize(find.byKey(ValueKey(key))),
          const Size.square(QuarkBarIconButton.size),
          reason: key,
        );
      }
      expect(find.byKey(const ValueKey('file_top_bar_home')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide: the create chips and view toggles sit in the path row', (
    tester,
  ) async {
    await pumpBar(tester, wide);

    expect(find.byKey(const ValueKey('file_top_bar_upload')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file_top_bar_new_folder')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file_top_bar_new_file')), findsOneWidget);
    expect(find.byKey(const ValueKey('bar_segment_grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('app_bar_bottom_menu')), findsNothing);
  });

  testWidgets('narrow: they collapse into the labeled Views menu', (
    tester,
  ) async {
    await pumpBar(tester, narrow);

    expect(find.byKey(const ValueKey('file_top_bar_upload')), findsNothing);
    final menu = find.byKey(const ValueKey('app_bar_bottom_menu'));
    expect(
      find.descendant(of: menu, matching: find.text('Views')),
      findsOneWidget,
    );

    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('file_top_bar_views_grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search hides the path row', (tester) async {
    await pumpBar(tester, wide, isSearchMode: true);

    expect(find.byKey(const ValueKey('file_top_bar_home')), findsNothing);
    expect(find.byKey(const ValueKey('file_top_bar_search')), findsOneWidget);
  });
}
