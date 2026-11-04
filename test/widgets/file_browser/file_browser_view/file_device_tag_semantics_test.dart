import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_device_group.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_tile.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #3937: a device tag's tooltip merged into the Files row, the grid tile,
/// and the per-device header. Flutter web names a node with its tooltip and
/// then its label, so every file was read as its first drive.

const _internal = FileDevice(serial: '', name: 'Built-in storage');
const _media = FileDevice(serial: 'A1', name: 'Media drive');

const _folder = FileNode(
  name: 'Trip 2026',
  size: 0,
  isDir: true,
  deviceName: 'Built-in storage',
  devicePath: '',
  deviceSerial: '',
  dirPath: 'Trip 2026',
  devices: [_internal, _media],
);

/// What Flutter web assigns as the node's name: the tooltip, then the label.
String _webName(SemanticsNode node) {
  if (node.tooltip.isEmpty) return node.label;
  if (node.label.isEmpty) return node.tooltip;
  return '${node.tooltip}\n${node.label}';
}

int _occurrences(String text, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(text).length;

/// The merged name starts with the file, each drive is read once, and the
/// tag's tooltip is not part of the node.
void _expectNamesTheFile(SemanticsNode node) {
  final name = _webName(node);
  expect(name, startsWith(_folder.name), reason: name);
  for (final device in _folder.onDevices) {
    expect(_occurrences(name, device.name), 1, reason: name);
  }
  expect(node.tooltip, isEmpty, reason: 'tooltip text in the node');
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [QuarkTokens.light]),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a list row on two drives is named for the file', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FileBrowserListTile(
        item: _folder,
        isSelected: false,
        extractingPaths: const {},
        showFileSizeAndMenu: true,
        columns: const [FileListColumn.modified, FileListColumn.device],
        inArchive: false,
        isSearchMode: false,
        selectionMode: false,
        onDispatchMenuAction: (_, _, _) {},
        onOpenDirectory: (_) {},
      ),
    );

    expect(tester.takeException(), isNull);
    _expectNamesTheFile(tester.getSemantics(find.text(_folder.name)));
    handle.dispose();
  });

  testWidgets('a grid tile on two drives is named for the file', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 220,
          child: FileGridTile(
            item: _folder,
            menu: FileMenu(
              item: _folder,
              menuActions: FileBrowserView.defaultMenuActions,
              extractingPaths: const {},
              inArchive: false,
              isSearchMode: false,
              onDispatchMenuAction: (_, _, _) {},
            ),
            isSelected: false,
            selectionMode: false,
            showFileSizeAndMenu: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    _expectNamesTheFile(tester.getSemantics(find.text(_folder.name)));
    handle.dispose();
  });

  testWidgets('a per-device header names its drive once, with the count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const FileDeviceGroup(
        device: _internal,
        itemCount: 4,
        children: [SizedBox.shrink()],
      ),
    );

    expect(tester.takeException(), isNull);
    final node = tester.getSemantics(find.text('4 items'));
    final name = _webName(node);
    expect(_occurrences(name, _internal.name), 1, reason: name);
    expect(name, contains('4 items'), reason: name);
    expect(node.tooltip, isEmpty, reason: 'tooltip text in the node');
    handle.dispose();
  });
}
