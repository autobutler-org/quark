import 'package:quark/utils/cache_manager_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/decode_once_image.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';

/// #3355: opening a photo and closing the viewer reused list slots by index,
/// so the row for one file painted the next file's thumbnail.
FileNode _image(String name) => FileNode(
  name: name,
  size: 128,
  isDir: false,
  deviceName: 'Quark',
  devicePath: '',
  deviceSerial: 'internal',
  dirPath: 'users/me/$name',
);

/// The thumbnail URL an [Image] built by `ThumbnailCacheManager.image` loads.
String _urlOf(Image image) =>
    (((image.image as DecodeOnceImage).image as ResizeImage).imageProvider
            as CacheManagerImage)
        .url;

const _names = [
  'files-photo-0003.jpg',
  'files-photo-0004.jpg',
  'files-photo-0005.jpg',
  'files-photo-0006.jpg',
];

/// The test binding answers every request with HTTP 400, and a shimmer keeps
/// a frame scheduled. Unmount, then fail if an image error escaped.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'each row thumbnail stays on its file after the viewer route pops',
    (tester) async {
      final nodes = [for (final name in _names) _image(name)];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FileBrowserView(
                filesFuture: Future.value(nodes),
                initialData: nodes,
                currentPath: 'users/me',
                isGridView: false,
                onFileMenuAction: (_, _) async {},
                onOpenDirectory: (node) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text('viewing ${node.name}')),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('files-photo-0004.jpg'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('viewing files-photo-0004.jpg'), findsOneWidget);
      // The listing stays mounted under the viewer. A disposed list would
      // build fresh thumbnails and hide a slot reused by index.
      expect(find.text('files-photo-0003.jpg'), findsOneWidget);

      Navigator.of(
        tester.element(find.text('viewing files-photo-0004.jpg')),
      ).pop();
      // The route's reverse transition is 300ms. A shimmer under the list
      // keeps a frame scheduled, so advance the clock in steps instead of
      // waiting for the tree to go idle.
      for (
        var i = 0;
        i < 8 &&
            find.text('viewing files-photo-0004.jpg').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('viewing files-photo-0004.jpg'), findsNothing);

      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final tile = find.widgetWithText(FileBrowserListTile, node.name);
        expect(tile, findsOneWidget);
        final image = tester.widget<Image>(
          find.descendant(of: tile, matching: find.byType(Image)),
        );
        // Device serial and path, never the row's list index.
        expect(image.key, ValueKey('${node.deviceSerial}:${node.apiPath}'));
        expect(image.key, isNot(ValueKey<int>(i)));
        final url = Uri.parse(_urlOf(image));
        expect(url.path, contains(node.name));
        expect(url.queryParameters['serial'], node.deviceSerial);
        if (i + 1 < nodes.length) {
          expect(url.path, isNot(contains(nodes[i + 1].name)));
        }
      }

      await _finish(tester);
    },
  );
}
