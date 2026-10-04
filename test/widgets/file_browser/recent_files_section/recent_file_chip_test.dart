import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/recent_files_section/recent_file_chip.dart';

import '../../../support/tap_target_guidelines.dart';

/// #2603, #2605: the chip and its "Go to folder" badge are both labeled
/// targets a finger can hit.
void main() {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    for (final deviceName in ['', 'disk']) {
      final device = deviceName.isEmpty ? 'no device' : 'a device';
      testWidgets('the chip and its badge are 48dp with $device ($label)', (
        tester,
      ) async {
        setViewport(tester, size);
        final events = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RecentFileChip(
                  file: FileNode(
                    name: 'a.txt',
                    size: 1,
                    isDir: false,
                    deviceName: deviceName,
                    devicePath: '/mnt/disk',
                    deviceSerial: 'serial',
                    dirPath: '/docs/a.txt',
                  ),
                  onTap: () => events.add('open'),
                  onFolderTap: () => events.add('folder'),
                ),
              ),
            ),
          ),
        );

        final badge = find.byKey(const ValueKey('recent_file_folder_a.txt'));
        expect(tester.getSize(badge).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(badge).height, greaterThanOrEqualTo(48));
        // The badge's edge, well clear of its 14px glyph, still lands.
        await tester.tapAt(tester.getCenter(badge) + const Offset(20, 0));
        await tester.tap(find.text('a.txt'));
        expect(events, ['folder', 'open']);

        await expectTapTargetGuidelines(tester);
      });
    }
  }
}
