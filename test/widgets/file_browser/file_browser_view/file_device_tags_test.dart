import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' show setViewport;
import '../../../support/text_scale.dart' show narrowViewport, wideViewport;

const _internal = FileDevice(serial: '', name: 'Internal');
const _usb = FileDevice(serial: 'A1', name: 'Backup');

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
  const FileNode(
    name: 'notes.txt',
    size: 10,
    isDir: false,
    deviceName: 'Backup',
    devicePath: '',
    deviceSerial: 'A1',
    dirPath: 'notes.txt',
  ),
];

/// #1869: the list row, the grid tile and the per-device group header name
/// the device in a colored tag.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    bool isGridView = false,
    bool isUnifiedView = true,
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
            isUnifiedView: isUnifiedView,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final (label, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    for (final isGridView in [false, true]) {
      final view = isGridView ? 'grid' : 'list';
      testWidgets('a $view item tags every device it is on ($label)', (
        tester,
      ) async {
        await pump(tester, size, isGridView: isGridView);

        // The merged folder carries both drives; the file only its own.
        expect(find.byKey(const ValueKey('device_tag_')), findsOneWidget);
        expect(find.byKey(const ValueKey('device_tag_A1')), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('each device tag has its own color', (tester) async {
    await pump(tester, wideViewport);

    Color colorOf(String key) =>
        tester.widget<DeviceTag>(find.byKey(ValueKey(key)).first).color;
    expect(colorOf('device_tag_'), isNot(colorOf('device_tag_A1')));
  });

  testWidgets('a per-device group header is the device tag', (tester) async {
    await pump(tester, wideViewport, isUnifiedView: false);

    expect(find.byKey(const ValueKey('device_group_tag_')), findsOneWidget);
    expect(find.byKey(const ValueKey('device_group_tag_A1')), findsOneWidget);
  });
}
