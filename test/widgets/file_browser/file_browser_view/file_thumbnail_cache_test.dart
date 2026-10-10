import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';

/// #1777: the file browser keyed its disk cache by the thumbnail URL, token
/// and all, so signing in again downloaded every thumbnail a second time.
void main() {
  final item = FileNode(
    name: 'mountain.png',
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
    testWidgets('the $label caches its thumbnail under the token-free key', (
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
      expect(
        cached.cacheKey,
        ThumbnailCacheManager.keyFor(Uri.parse(cached.imageUrl)),
      );
      expect(cached.cacheManager, same(ThumbnailCacheManager.instance));

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
