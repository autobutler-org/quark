import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/layout/file_library_page.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #4105: the page Docs, Sheets and Slides share puts the title, the create
/// chip, the search bar, the optional bottom row and the listing where each
/// page had them, on a phone and on a desktop.
void main() {
  late TextEditingController search;
  late int created;
  late int refreshed;

  setUp(() {
    search = TextEditingController();
    created = 0;
    refreshed = 0;
  });

  tearDown(() => search.dispose());

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    PreferredSizeWidget? bottom,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: FileLibraryPage(
          title: 'Docs',
          icon: QuarkIcons.description_outlined,
          drawerSection: QuarkDrawerSection.docs,
          keyPrefix: 'docs',
          createLabel: 'New document',
          onCreate: () => created++,
          searchController: search,
          searchHint: 'Search docs…',
          onRefresh: () async => refreshed++,
          isRefreshing: false,
          bottom: bottom,
          child: const Center(child: Text('the listing')),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('lays out at ${size.width.toInt()} wide', (tester) async {
      await pump(
        tester,
        size,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: Text('the bottom row', key: ValueKey('bottom_row')),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.byType(FileTypeSearchBar), findsOneWidget);
      expect(find.byKey(const ValueKey('docs_search')), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom_row')), findsOneWidget);
      expect(find.text('the listing'), findsOneWidget);
      // The listing sits under the search bar.
      expect(
        tester.getTopLeft(find.text('the listing')).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(FileTypeSearchBar)).dy,
        ),
      );
    });
  }

  testWidgets('the create chip and refresh call back', (tester) async {
    await pump(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('docs_new')));
    expect(created, 1);
    await tester.tap(find.byType(RefreshIconButton));
    expect(refreshed, 1);
  });

  testWidgets('no bottom row unless one is given', (tester) async {
    await pump(tester, const Size(1280, 800));
    expect(find.byKey(const ValueKey('bottom_row')), findsNothing);
  });
}
