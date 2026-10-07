import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_views_menu.dart';

import '../../../support/tap_target_guidelines.dart';

StorageDevice _device(String name) => StorageDevice(
  name: name,
  devicePath: '/dev/$name',
  mountPoint: '/mnt/$name',
  fileSystem: 'ext4',
  totalBytes: 1,
  usedBytes: 0,
  availableBytes: 1,
  isInternal: false,
  isEnabled: true,
);

/// #2603, #2605: the compact Views menu's rows are 48dp, and the layout rows
/// say which one is chosen.
void main() {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('every row is a labeled 48dp target ($label)', (tester) async {
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: FileTopBarViewsMenu(
                  isGridView: true,
                  isUnifiedView: false,
                  onToggleView: () {},
                  onToggleUnifiedView: () {},
                  devices: [_device('sda'), _device('sdb')],
                  activeDevicePaths: const {'/dev/sda'},
                  onDeviceToggled: (_) {},
                  columns: const {FileListColumn.modified},
                  onColumnToggled: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('file_top_bar_views_grid')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('file_top_bar_views_list')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      handle.dispose();

      await expectTapTargetGuidelines(tester);
    });

    // #1566: the compact layout's column picker.
    testWidgets('a Columns section checks and toggles the columns ($label)', (
      tester,
    ) async {
      setViewport(tester, size);
      final toggles = <(FileListColumn, bool)>[];
      Future<void> pump({required bool enabled}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FileTopBarViewsMenu(
                isGridView: false,
                isUnifiedView: true,
                onToggleView: () {},
                onToggleUnifiedView: () {},
                columns: const {FileListColumn.modified, FileListColumn.size},
                onColumnToggled: enabled
                    ? (column, visible) => toggles.add((column, visible))
                    : null,
              ),
            ),
          ),
        ),
      );
      Finder box(FileListColumn column) =>
          find.byKey(ValueKey('file_top_bar_views_column_${column.name}'));

      await pump(enabled: true);
      expect(tester.takeException(), isNull);
      expect(find.text('COLUMNS'), findsOneWidget);
      for (final column in FileListColumn.values) {
        expect(
          tester.widget<CheckboxListTile>(box(column)).value,
          column == FileListColumn.modified || column == FileListColumn.size,
          reason: column.name,
        );
      }

      await tester.tap(box(FileListColumn.device));
      await tester.tap(box(FileListColumn.modified));
      expect(toggles, [
        (FileListColumn.device, true),
        (FileListColumn.modified, false),
      ]);

      // Nothing to call: the grid, which has no columns to choose.
      await pump(enabled: false);
      await tester.tap(box(FileListColumn.kind));
      expect(toggles, hasLength(2));
    });
  }
}
