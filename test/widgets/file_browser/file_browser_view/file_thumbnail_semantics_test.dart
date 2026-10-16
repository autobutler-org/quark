import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';

/// #2603: the row or tile around a file thumbnail already reads the file's
/// name, so the decoded thumbnail stays out of the semantics tree.
void main() {
  final item = FileNode(
    name: 'beach.png',
    size: 128,
    isDir: false,
    deviceName: 'Quark',
    devicePath: '',
    deviceSerial: '',
    dirPath: '',
  );
  for (final (label, widget) in [
    ('list leading', FileListLeading(item: item)),
    ('grid preview', FileGridPreview(item: item)),
  ]) {
    testWidgets('the $label thumbnail is excluded from semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox.square(dimension: 120, child: widget)),
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
        isTrue,
      );
      // The test binding answers every request with HTTP 400, and a shimmer
      // keeps a frame scheduled. Unmount, then fail if an error escaped.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
