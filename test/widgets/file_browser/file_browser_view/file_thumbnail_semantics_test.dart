import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
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
  // A 1x1 transparent PNG, so the image decodes cleanly.
  final provider = MemoryImage(
    Uint8List.fromList(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]),
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
      final cached = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // The binding never decodes a network image, so build the loaded state
      // the way CachedNetworkImage would.
      final loaded = cached.imageBuilder!(
        tester.element(find.byType(CachedNetworkImage)),
        provider,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox.square(dimension: 120, child: loaded)),
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
