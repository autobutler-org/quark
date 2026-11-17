import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/layout/file_library_page.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #4105: the page Docs, Sheets and Slides share puts the title, the create
/// chip, the search bar, the optional bottom row and the listing where each
/// page had them, on a phone and on a desktop. #4227: a phone trades the chip
/// and the bottom row for the + button, under a search field at least 44 px tall.
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
    VoidCallback? onPhoneCreate,
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
          onPhoneCreate: onPhoneCreate,
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

  const bottomRow = PreferredSize(
    preferredSize: Size.fromHeight(40),
    child: Text('the bottom row', key: ValueKey('bottom_row')),
  );

  testWidgets('a phone has the + button, not the chip or the bottom row', (
    tester,
  ) async {
    await pump(tester, const Size(360, 640), bottom: bottomRow);
    expect(find.byKey(const ValueKey('docs_new')), findsNothing);
    expect(find.byKey(const ValueKey('bottom_row')), findsNothing);
    expect(find.byType(QuarkCreateFab), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('docs_create_fab')));
    expect(created, 1);
  });

  testWidgets('a phone + runs onPhoneCreate when the page gives one', (
    tester,
  ) async {
    var sheets = 0;
    await pump(tester, const Size(360, 640), onPhoneCreate: () => sheets++);
    await tester.tap(find.byKey(const ValueKey('docs_create_fab')));
    expect(sheets, 1);
    expect(created, 0);
  });

  testWidgets('a wide screen keeps the chip and the bottom row', (
    tester,
  ) async {
    await pump(tester, const Size(1280, 800), bottom: bottomRow);
    expect(find.byKey(const ValueKey('docs_new')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_row')), findsOneWidget);
    expect(find.byType(QuarkCreateFab), findsNothing);
  });

  testWidgets('the + fades while the listing scrolls down', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
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
          onRefresh: () async {},
          isRefreshing: false,
          child: ListView(
            children: [for (var i = 0; i < 60; i++) Text('row $i')],
          ),
        ),
      ),
    );
    await tester.pump();
    QuarkCreateFab fab() =>
        tester.widget<QuarkCreateFab>(find.byType(QuarkCreateFab));
    expect(fab().visible, isTrue);
    await tester.drag(find.text('row 5'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(fab().visible, isFalse);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(fab().visible, isTrue);
  });

  testWidgets('the phone search field is at least 44 px tall with 16 px text', (
    tester,
  ) async {
    await pump(tester, const Size(360, 640));
    final field = find.byKey(const ValueKey('docs_search'));
    expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
    final text = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(text.style.fontSize, greaterThanOrEqualTo(16));
    // The field centers its text and its clear button.
    await tester.enterText(field, 'notes');
    await tester.pump();
    expect(tester.takeException(), isNull);
    final middle = tester.getCenter(field).dy;
    expect(tester.getCenter(find.byType(EditableText)).dy, closeTo(middle, 2));
    expect(
      tester.getCenter(find.byKey(const ValueKey('docs_search_clear'))).dy,
      closeTo(middle, 2),
    );
    // Directly under the bar: nothing between the bar and the field's strip.
    expect(
      tester.getTopLeft(find.byType(FileTypeSearchBar)).dy,
      tester.getBottomLeft(find.byType(QuarkAppBar)).dy,
    );
  });
}
