import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header.dart';
import 'package:quark/widgets/file_browser/file_sort_view_row.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart'
    show narrowViewport, setViewport, wideViewport;

// #4226: at 390 px the list kept the desktop's columns, so Modified and Size
// got about 40 px each and every date read "Nov 1..." and every size
// "224.7...". Below the split view's breakpoint each row is now the name over
// one muted line that says when and how big, and sorting moved from the
// column headers into a "Sort and view" sheet.
//
// Laid out in Roboto, as on Android: the test font draws every glyph a full
// em wide, which would make every line far wider than it is on a phone.
void main() {
  setUpAll(() async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in const ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(
        File(
          '$fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
  });
  final roboto = ThemeData(fontFamily: 'Roboto');

  final photo = FileNode(
    name: 'IMG_4021.jpg',
    size: 3355443,
    isDir: false,
    deviceName: 'Internal',
    devicePath: '',
    deviceSerial: '',
    dirPath: '',
    modifiedAt: DateTime(2025, 11, 10, 9),
  );
  final folder = FileNode(
    name: 'Documents',
    size: 0,
    isDir: true,
    deviceName: 'Internal',
    devicePath: '',
    deviceSerial: '',
    dirPath: '',
    modifiedAt: DateTime(2025, 11, 14, 9),
  );

  Future<void> pumpList(
    WidgetTester tester, {
    required Size size,
    required bool compact,
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: roboto,
        home: Scaffold(
          body: FileBrowserView(
            filesFuture: Future.value([folder, photo]),
            currentPath: '',
            onFileMenuAction: (_, _) async {},
            onOpenDirectory: (_) {},
            isGridView: false,
            compact: compact,
            columns: const {},
          ),
        ),
      ),
    );
    // The listing resolves on the next frame. Not pumpAndSettle: a
    // thumbnail's loader never settles.
    await tester.pump();
    await tester.pump();
  }

  void expectWhole(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: text);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" has to be read whole, not cut short',
    );
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('a phone row shows a full date and size ($label)', (
      tester,
    ) async {
      await pumpList(tester, size: size, compact: true);

      expectWhole(tester, 'Nov 10, 2025 · 3.2 MB');
      expectWhole(tester, 'Folder · Nov 14, 2025');
      expect(find.byType(FileSortHeader), findsNothing);

      for (final row in tester.widgetList<FileBrowserListTile>(
        find.byType(FileBrowserListTile),
      )) {
        final rect = tester.getRect(find.byWidget(row));
        expect(rect.height, greaterThanOrEqualTo(56), reason: row.item.name);
      }
      for (final menu in find.byType(FileMenuButton).evaluate()) {
        final box = menu.renderObject! as RenderBox;
        expect(box.size.width, greaterThanOrEqualTo(44));
        expect(box.size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wide list keeps its column header ($label)', (
      tester,
    ) async {
      await pumpList(tester, size: size, compact: false);

      expect(find.byType(FileSortHeader), findsOneWidget);
      expect(find.text('Nov 10, 2025 · 3.2 MB'), findsNothing);
    });
  }

  group('fileRowMetaText', () {
    final now = DateTime(2026, 11, 16, 15);

    FileNode node({required bool isDir, DateTime? at, int size = 48230}) =>
        FileNode(
          name: 'x',
          size: size,
          isDir: isDir,
          deviceName: '',
          devicePath: '',
          deviceSerial: '',
          dirPath: '',
          modifiedAt: at,
        );

    test('a file changed today reads Today and its size', () {
      expect(
        fileRowMetaText(node(isDir: false, at: DateTime(2026, 11, 16, 8)), now),
        'Today · 47.1 KB',
      );
    });

    test('a folder reads Folder and its date in this year', () {
      expect(
        fileRowMetaText(node(isDir: true, at: DateTime(2026, 11, 14)), now),
        'Folder · Nov 14',
      );
    });

    test('yesterday and earlier years read as such', () {
      expect(
        fileRowMetaText(node(isDir: false, at: DateTime(2026, 11, 15)), now),
        'Yesterday · 47.1 KB',
      );
      expect(
        fileRowMetaText(node(isDir: false, at: DateTime(2024, 3, 2)), now),
        'Mar 2, 2024 · 47.1 KB',
      );
    });

    test('a node with no time reads only what it has', () {
      expect(fileRowMetaText(node(isDir: true), now), 'Folder');
      expect(fileRowMetaText(node(isDir: false), now), '47.1 KB');
    });
  });

  group('FileSortViewRow', () {
    Future<List<String>> pumpRow(WidgetTester tester) async {
      final log = <String>[];
      setViewport(tester, narrowViewport);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FileSortViewRow(
                  lead: const Text('My files'),
                  sortColumn: SortColumn.name,
                  sortDirection: SortDirection.asc,
                  isGridView: false,
                  isUnifiedView: true,
                  onSortChanged: (c, d) => log.add('sort ${c.name} ${d.name}'),
                  onToggleView: () => log.add('view'),
                  onToggleUnifiedView: () => log.add('grouping'),
                ),
              ],
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('the chip reads the sort and opens the sheet', (tester) async {
      await pumpRow(tester);

      final chip = find.byKey(const ValueKey('file_sort_view_chip'));
      expect(find.descendant(of: chip, matching: find.text('Name')), findsOne);

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.byType(FileSortViewSheet), findsOneWidget);
      for (final key in [
        'file_sort_view_sort_name',
        'file_sort_view_sort_modified',
        'file_sort_view_sort_size',
        'file_sort_view_ascending',
        'file_sort_view_descending',
        'file_sort_view_list',
        'file_sort_view_grid',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a choice applies and closes the sheet', (tester) async {
      final log = await pumpRow(tester);

      await tester.tap(find.byKey(const ValueKey('file_sort_view_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file_sort_view_sort_size')));
      await tester.pumpAndSettle();

      expect(log, ['sort size asc']);
      expect(find.byType(FileSortViewSheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('file_sort_view_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file_sort_view_descending')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file_sort_view_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file_sort_view_grid')));
      await tester.pumpAndSettle();

      expect(log, ['sort size asc', 'sort name desc', 'view']);
    });
  });
}
