import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:quark_icons/quark_icons.dart';

final _file = FileNode(
  name: 'notes.txt',
  size: 12,
  isDir: false,
  deviceName: 'Quark',
  devicePath: '',
  deviceSerial: '',
  dirPath: 'Documents',
);

/// Where the finger lands: over the row, well away from the three-dot button
/// on the right edge.
const _press = Offset(60, 20);

List<String> _entries(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(PopupMenuItem<FileMenuAction>),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data!)
    .toList();

Future<void> _pumpTile(
  WidgetTester tester, {
  bool selectionMode = false,
  bool inArchive = false,
  void Function(FileNode)? onSelectionChanged,
  void Function(FileNode, FileMenuAction)? onAction,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: FileBrowserListTile(
        item: _file,
        isSelected: false,
        extractingPaths: const {},
        showFileSizeAndMenu: true,
        inArchive: inArchive,
        isSearchMode: false,
        selectionMode: selectionMode,
        onDispatchMenuAction: (_, item, action) => onAction?.call(item, action),
        onOpenDirectory: (_) {},
        onSelectionChanged: onSelectionChanged,
      ),
    ),
  ),
);

void main() {
  testWidgets('a long press opens the row menu without selecting', (
    tester,
  ) async {
    var selections = 0;
    await _pumpTile(tester, onSelectionChanged: (_) => selections++);

    await tester.longPressAt(_press);
    await tester.pumpAndSettle();

    expect(_entries(tester), ['Download', 'Move/Rename', 'Share…', 'Delete']);
    expect(selections, 0);
  });

  testWidgets('the menu opens at the press, not at the three-dot button', (
    tester,
  ) async {
    await _pumpTile(tester);
    final buttonX = tester.getCenter(find.byIcon(QuarkIcons.more_vert)).dx;

    await tester.longPressAt(_press);
    await tester.pumpAndSettle();

    final menuX = tester
        .getTopLeft(find.byType(PopupMenuItem<FileMenuAction>).first)
        .dx;
    expect(buttonX, greaterThan(600), reason: 'the button sits on the right');
    expect(menuX, closeTo(_press.dx, 40));
  });

  testWidgets('picking an entry dispatches its action', (tester) async {
    FileMenuAction? dispatched;
    await _pumpTile(tester, onAction: (_, action) => dispatched = action);

    await tester.longPressAt(_press);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(dispatched, FileMenuAction.delete);
  });

  // In selection mode a held press is just a slow tap, as it was before the
  // menu moved onto the long press: it toggles the row and opens nothing.
  testWidgets('a long press opens no menu in selection mode', (tester) async {
    await _pumpTile(tester, selectionMode: true, onSelectionChanged: (_) {});

    await tester.longPressAt(_press);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<FileMenuAction>), findsNothing);
  });

  testWidgets('inside an archive the menu still offers Download', (
    tester,
  ) async {
    await _pumpTile(tester, inArchive: true);

    await tester.longPressAt(_press);
    await tester.pumpAndSettle();

    expect(_entries(tester), ['Download']);
  });

  testWidgets('a long press opens the menu on a grid tile too', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileBrowserView(
            filesFuture: Future.value([_file]),
            onFileMenuAction: (_, _) async {},
            onOpenDirectory: (_) {},
            isGridView: true,
            currentPath: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPressAt(tester.getCenter(find.text('notes.txt')));
    await tester.pumpAndSettle();

    expect(_entries(tester), ['Download', 'Move/Rename', 'Share…', 'Delete']);
  });
}
