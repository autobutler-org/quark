import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_device_group.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_tile.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' show setViewport;
import '../../../support/text_scale.dart' show narrowViewport, wideViewport;

const _internal = FileDevice(serial: '', name: 'Internal');
const _usb = FileDevice(serial: 'A1', name: 'Backup');

FileNode _file(String name, FileDevice device) => FileNode(
  name: name,
  size: 10,
  isDir: false,
  deviceName: device.name,
  devicePath: '',
  deviceSerial: device.serial,
  dirPath: name,
);

final _files = [
  // A folder on both drives, as the merged listing reports it (#1868).
  const FileNode(
    name: 'Shared',
    size: 0,
    isDir: true,
    deviceName: 'Internal',
    devicePath: '',
    deviceSerial: '',
    dirPath: 'Shared',
    devices: [_internal, _usb],
  ),
  _file('home.txt', _internal),
  _file('backup.txt', _usb),
];

/// #1870: the per-device view groups the grid and search results by device,
/// the way it already grouped the list.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    required bool isGridView,
    bool isSearchMode = false,
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [QuarkTokens.light]),
        home: Scaffold(
          body: FileBrowserView(
            filesFuture: Future.value(_files),
            initialData: _files,
            currentPath: '',
            onFileMenuAction: (_, _) async {},
            onOpenDirectory: (_) {},
            isGridView: isGridView,
            isUnifiedView: false,
            isSearchMode: isSearchMode,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder groupOf(FileDevice device) =>
      find.byWidgetPredicate((w) => w is FileDeviceGroup && w.device == device);

  /// The item names listed under [device]'s group, scrolled into view: the
  /// second group of a grid starts below a narrow screen.
  Future<Set<String>> namesIn(WidgetTester tester, FileDevice device) async {
    final group = groupOf(device);
    // The page's own list, not a group's grid inside it.
    await tester.scrollUntilVisible(
      group,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    return {
      for (final text in tester.widgetList<Text>(
        find.descendant(of: group, matching: find.byType(Text)),
      ))
        ?text.data,
    };
  }

  for (final (label, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    for (final isGridView in [false, true]) {
      for (final isSearchMode in [false, true]) {
        final view =
            '${isGridView ? 'grid' : 'list'}'
            '${isSearchMode ? ' search results' : ''}';
        testWidgets('the $view groups items by device ($label)', (
          tester,
        ) async {
          await pump(
            tester,
            size,
            isGridView: isGridView,
            isSearchMode: isSearchMode,
          );

          // The merged folder is under each drive it is on.
          final internal = await namesIn(tester, _internal);
          expect(internal, containsAll(['Shared', 'home.txt']));
          expect(internal, isNot(contains('backup.txt')));
          expect(
            find.descendant(
              of: groupOf(_internal),
              matching: find.byType(FileGridTile),
            ),
            isGridView ? findsNWidgets(2) : findsNothing,
          );
          final usb = await namesIn(tester, _usb);
          expect(usb, containsAll(['Shared', 'backup.txt']));
          expect(usb, isNot(contains('home.txt')));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
