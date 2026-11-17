import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_device_tags.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' show setViewport;

/// #3936: on a grid tile and in a narrow list, a file on several drives
/// showed a row of empty pills, and two drives could share a color.

const _internal = FileDevice(serial: '', name: 'Built-in storage');
const _media = FileDevice(serial: 'LAB-MEDIA-01', name: 'Media drive');
const _archive = FileDevice(
  serial: 'LAB-ARCH-02',
  name: 'Family archive drive 4TB',
);

FileNode _node(String name, List<FileDevice> devices) => FileNode(
  name: name,
  size: 0,
  isDir: true,
  deviceName: devices.first.name,
  devicePath: '',
  deviceSerial: devices.first.serial,
  dirPath: name,
  devices: devices,
);

final _files = [
  _node('One', const [_internal]),
  _node('Two', const [_internal, _media]),
  _node('Three', const [_internal, _media, _archive]),
];

/// A tag reads as something: its whole label, or at least a few letters
/// before the ellipsis. An empty pill or a lone "…" fails.
void _expectReadable(WidgetTester tester, Finder tag) {
  final text = find.descendant(of: tag, matching: find.byType(Text));
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final label = tester.widget<Text>(text).data!;
  if (!paragraph.didExceedMaxLines) return;
  // How many characters fit before the ellipsis.
  final shown = paragraph
      .getPositionForOffset(Offset(paragraph.size.width, 1))
      .offset;
  expect(shown, greaterThanOrEqualTo(4), reason: '"$label" shows $shown');
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    required bool grid,
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
            isGridView: grid,
            isUnifiedView: isUnifiedView,
            columns: const {FileListColumn.device},
            deviceSerials: const ['', 'LAB-MEDIA-01', 'LAB-ARCH-02'],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Below 900 dp the Files page lists one compact line per file with no
  // columns (#4226), so the device column is checked where it shows.
  for (final (label, size, grids) in [
    ('360', const Size(360, 640), [true]),
    ('390', const Size(390, 844), [true]),
    ('1280', const Size(1280, 800), [true, false]),
  ]) {
    for (final grid in grids) {
      final view = grid ? 'grid tile' : 'list row';
      testWidgets('a $view names its drives readably at $label', (
        tester,
      ) async {
        await pump(tester, size, grid: grid);
        expect(tester.takeException(), isNull);

        for (final file in _files) {
          await tester.scrollUntilVisible(find.text(file.name), 100);
          final row = find.ancestor(
            of: find.text(file.name),
            matching: find.byType(grid ? Card : ListTile),
          );
          final tags = find.descendant(
            of: find.descendant(of: row, matching: find.byType(FileDeviceTags)),
            matching: find.byType(DeviceTag),
          );
          final shown = tags.evaluate().length;
          expect(shown, greaterThan(0), reason: file.name);
          for (var i = 0; i < shown; i++) {
            _expectReadable(tester, tags.at(i));
          }
          // A summary names every drive it stands for to a screen reader.
          final read = [
            for (var i = 0; i < shown; i++)
              tester.widget<DeviceTag>(tags.at(i)).semanticLabel ??
                  tester.widget<DeviceTag>(tags.at(i)).label,
          ].join(', ');
          for (final device in file.onDevices) {
            expect(read, contains(device.name), reason: file.name);
          }
        }
      });
    }
  }

  testWidgets('the drives on one Quark never share a color', (tester) async {
    // '' and LAB-MEDIA-01 hash to the same color.
    await pump(
      tester,
      const Size(1280, 800),
      grid: false,
      isUnifiedView: false,
    );

    final colors = {
      for (final serial in ['', 'LAB-MEDIA-01', 'LAB-ARCH-02'])
        tester
            .widget<DeviceTag>(find.byKey(ValueKey('device_group_tag_$serial')))
            .color,
    };
    expect(colors, hasLength(3));
  });
}
