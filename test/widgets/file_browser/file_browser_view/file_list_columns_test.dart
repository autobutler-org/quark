import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';

import '../../../support/text_scale.dart' show narrowViewport, wideViewport;

FileNode _node(
  String name, {
  DateTime? modifiedAt,
  bool isDir = false,
  int size = 2048,
}) => FileNode(
  name: name,
  size: size,
  isDir: isDir,
  deviceName: 'Attic',
  devicePath: '/dev/sda',
  deviceSerial: '',
  dirPath: name,
  modifiedAt: modifiedAt,
);

final _files = [
  _node('budget.csv', modifiedAt: DateTime(2026, 10, 6, 14, 30)),
  _node('archive.zip', modifiedAt: DateTime(2024, 1, 2)),
  _node('notes.txt'),
  _node('Taxes', isDir: true, modifiedAt: DateTime(2025, 3, 9)),
];

/// #1565, #1566: the list view shows the columns it is handed, header and
/// rows alike, and sorts by any of them.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    Set<FileListColumn>? columns,
    bool showFileSizeAndMenu = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: columns == null
              ? FileBrowserView(
                  filesFuture: Future.value(_files),
                  initialData: _files,
                  currentPath: '',
                  onFileMenuAction: (_, _) async {},
                  onOpenDirectory: (_) {},
                  isGridView: false,
                  showFileSizeAndMenu: showFileSizeAndMenu,
                )
              : FileBrowserView(
                  filesFuture: Future.value(_files),
                  initialData: _files,
                  currentPath: '',
                  onFileMenuAction: (_, _) async {},
                  onOpenDirectory: (_) {},
                  isGridView: false,
                  showFileSizeAndMenu: showFileSizeAndMenu,
                  columns: columns,
                ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder header(SortColumn column) =>
      find.byKey(ValueKey('file_sort_header_${column.name}'));

  /// The row names, top to bottom.
  List<String> order(WidgetTester tester) {
    final names = [for (final file in _files) file.name];
    names.sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
    return names;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('every chosen column has a header and a cell ($label)', (
      tester,
    ) async {
      await pump(tester, size, columns: FileListColumn.values.toSet());

      expect(tester.takeException(), isNull);
      for (final column in FileListColumn.values) {
        expect(header(column.sortColumn), findsOneWidget, reason: column.name);
      }
      expect(find.text('Kind'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);
      // Kind, from the file's extension; a folder is a Folder.
      expect(find.text('Spreadsheet'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      // Modified, in the viewer's own time zone.
      expect(find.text('Oct 6, 2026'), findsOneWidget);
      expect(find.text('Jan 2, 2024'), findsOneWidget);
      // Size and Device, as before.
      expect(find.text('2.0 KB'), findsNWidgets(3));
      expect(find.text('Attic'), findsNWidgets(4));
      // The folder's size and the file with no time share one placeholder.
      expect(find.text('--'), findsNWidgets(2));
    });

    // The header and a row are built from the same columns at the same
    // flexes. A row's leading and trailing gutters are 16px wider than the
    // header's, which is as far as a label can sit from its cells.
    testWidgets('each cell sits under its header ($label)', (tester) async {
      await pump(tester, size, columns: FileListColumn.values.toSet());

      final cells = ['Spreadsheet', 'Oct 6, 2026', 'Attic', '2.0 KB'];
      for (final (i, column) in FileListColumn.values.indexed) {
        final cell = find
            .ancestor(
              of: find.text(cells[i]).first,
              matching: find.byType(Expanded),
            )
            .first;
        expect(
          tester.getTopLeft(cell).dx,
          closeTo(tester.getTopLeft(header(column.sortColumn)).dx, 16),
          reason: column.name,
        );
      }
    });

    testWidgets('a column left out has no header and no cell ($label)', (
      tester,
    ) async {
      await pump(tester, size, columns: const {FileListColumn.modified});

      expect(header(SortColumn.name), findsOneWidget);
      expect(header(SortColumn.modified), findsOneWidget);
      expect(header(SortColumn.type), findsNothing);
      expect(header(SortColumn.size), findsNothing);
      expect(header(SortColumn.device), findsNothing);
      expect(find.text('Spreadsheet'), findsNothing);
      expect(find.text('2.0 KB'), findsNothing);
      expect(find.text('Attic'), findsNothing);
    });
  }

  // The trash and the folder picker pass no columns, and keep what they had.
  testWidgets('with no columns passed, the list shows Device and Size', (
    tester,
  ) async {
    await pump(tester, wideViewport);

    expect(header(SortColumn.device), findsOneWidget);
    expect(header(SortColumn.size), findsOneWidget);
    expect(header(SortColumn.type), findsNothing);
    expect(header(SortColumn.modified), findsNothing);
    expect(
      tester.getTopLeft(header(SortColumn.device)).dx,
      lessThan(tester.getTopLeft(header(SortColumn.size)).dx),
    );
  });

  testWidgets('a listing without sizes hides Size even when it is chosen', (
    tester,
  ) async {
    await pump(
      tester,
      wideViewport,
      columns: FileListColumn.values.toSet(),
      showFileSizeAndMenu: false,
    );

    expect(header(SortColumn.size), findsNothing);
    expect(find.text('2.0 KB'), findsNothing);
    expect(header(SortColumn.modified), findsOneWidget);
  });

  testWidgets('Modified sorts by time, a missing time oldest of all', (
    tester,
  ) async {
    await pump(tester, wideViewport, columns: const {FileListColumn.modified});

    await tester.tap(header(SortColumn.modified));
    await tester.pump();
    // Folders stay on top whatever the column.
    expect(order(tester), ['Taxes', 'notes.txt', 'archive.zip', 'budget.csv']);

    await tester.tap(header(SortColumn.modified));
    await tester.pump();
    expect(order(tester), ['Taxes', 'budget.csv', 'archive.zip', 'notes.txt']);
  });

  testWidgets('Kind sorts by the label the column shows', (tester) async {
    await pump(tester, wideViewport, columns: const {FileListColumn.kind});

    await tester.tap(header(SortColumn.type));
    await tester.pump();
    // Archive, Spreadsheet, Text.
    expect(order(tester), ['Taxes', 'archive.zip', 'budget.csv', 'notes.txt']);
  });
}
