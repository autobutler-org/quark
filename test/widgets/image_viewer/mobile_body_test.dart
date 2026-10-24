import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_drawer.dart';
import 'package:quark/widgets/image_viewer/mobile_body.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3359: on a phone the info sheet peeked with File info and Albums below
/// the screen edge, and neither its handle nor its rows dragged it up.
void main() {
  final metadata = PhotoMetadata(
    fileName: 'files-photo-0003-20220922.jpg',
    fileSize: 2400000,
    mtime: DateTime(2022, 9, 22, 14, 5),
    width: 4032,
    height: 3024,
    exif: PhotoExif(
      dateTaken: DateTime(2022, 9, 22, 14, 5),
      make: 'Google',
      model: 'Pixel 7',
      lens: 'Main camera',
      aperture: 1.9,
      shutterSpeed: '1/120',
      iso: 100,
      focalLength: 6.8,
      latitude: 48.8566,
      longitude: 2.3522,
    ),
    albums: const [
      AlbumRef(id: 1, name: 'Paris'),
      AlbumRef(id: 2, name: 'Favorites'),
    ],
  );

  Future<DraggableScrollableController> pumpBody(
    WidgetTester tester,
    Size size,
  ) async {
    setViewport(tester, size);
    final controller = DraggableScrollableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(title: const Text('photo')),
          body: MobileBody(
            photoArea: const SizedBox.expand(),
            sidebarOpen: true,
            drawerController: controller,
            name: metadata.fileName,
            metadata: metadata,
            loading: false,
            onAlbumTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Whether [finder] is on screen and not behind anything: a hit test at
  /// its center lands on it.
  bool reachable(WidgetTester tester, Finder finder) {
    // The list builds lazily, so a row far below the fold is not built.
    if (finder.evaluate().isEmpty) return false;
    final rect = tester.getRect(finder);
    final screen = Offset.zero & tester.view.physicalSize;
    if (!screen.contains(rect.center)) return false;
    final hits = tester.hitTestOnBinding(rect.center).path.map((e) => e.target);
    final target = tester.renderObject(finder);
    return hits.contains(target);
  }

  Finder handle() => find.byKey(const ValueKey('photo_info_handle'));

  for (final size in const [Size(412, 915), Size(360, 640)]) {
    group('at ${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('dragging the handle up opens the sheet to every row', (
        tester,
      ) async {
        final controller = await pumpBody(tester, size);
        final before = controller.size;
        expect(reachable(tester, find.text('Paris')), isFalse);

        await tester.drag(handle(), Offset(0, -size.height * 0.6));
        await tester.pumpAndSettle();

        expect(controller.size, greaterThan(before));
        await tester.dragUntilVisible(
          find.text('Favorites'),
          find.byType(ListView),
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
        expect(reachable(tester, find.text('FILE INFO')), isTrue);
        expect(reachable(tester, find.text('Favorites')), isTrue);
      });

      // A phone drags with a finger; a browser in device emulation, or a
      // narrow desktop window, drags with the mouse.
      for (final kind in const [
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      ]) {
        testWidgets('a ${kind.name} drag inside the sheet expands it, then '
            'scrolls it', (tester) async {
          final controller = await pumpBody(tester, size);
          final before = controller.size;

          // A slow, steady drag from the rows.
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('DATE & TIME')),
            kind: kind,
          );
          for (var i = 0; i < 40; i++) {
            await gesture.moveBy(const Offset(0, -25));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();

          expect(controller.size, greaterThan(before));
          expect(reachable(tester, find.text('Favorites')), isTrue);
        });
      }

      testWidgets('the handle is a drag target, not a dead strip', (
        tester,
      ) async {
        await pumpBody(tester, size);
        final drawer = tester.getRect(find.byType(MetadataDrawer));
        // The handle's hit area spans the sheet's width and is tall enough
        // for a thumb.
        final hit = tester.getRect(handle());
        expect(hit.width, drawer.width);
        expect(hit.height, greaterThanOrEqualTo(24));
      });
    });
  }
}
