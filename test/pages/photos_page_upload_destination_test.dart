import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/upload_drop_zone.dart';

/// #3192: where photos dropped on the Photos page go. Each test drops one
/// photo on the real page and reads the upload it sends, if any.
void main() {
  StorageDevice device(String name, {String serial = ''}) => StorageDevice(
    name: name,
    devicePath: '/dev/$name',
    mountPoint: '/mnt/$name',
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: serial.isEmpty,
    isEnabled: true,
    serial: serial,
  );

  /// Drops a photo on the page whose Quark lists [listDevices], and returns
  /// the serial of every upload sent.
  Future<List<String?>> dropPhoto(
    WidgetTester tester,
    Future<List<StorageDevice>> Function() listDevices,
  ) async {
    final uploads = <String?>[];
    final controller = PhotosController(
      // No device photos to ask for, on any platform: the real query is a
      // platform channel the test answers only on the real clock, so the
      // refresh after an upload would outlast pumpAndSettle under load (#3237).
      loadDeviceAssets: () async => [],
      listDevices: listDevices,
      readDroppedFile: (file) async => Uint8List.fromList([1]),
      renderDroppedFile: (file) async => null,
      uploadFiles:
          (
            path,
            files, {
            String? serial,
            bool overwrite = false,
            bool keepBoth = false,
          }) async {
            uploads.add(serial);
            return const [];
          },
    );
    await tester.pumpWidget(
      MaterialApp(home: PhotosPage(controller: controller)),
    );
    await tester.pump();

    final zone = tester.widget<UploadDropZone>(find.byType(UploadDropZone));
    zone.onDrop([
      DropItemFile.fromData(Uint8List.fromList([1]), path: 'a.jpg'),
    ]);
    await tester.pumpAndSettle();
    return uploads;
  }

  testWidgets('a failed device listing stops the upload and says so', (
    tester,
  ) async {
    const error = ApiException(500);
    final uploads = await dropPhoto(tester, () async => throw error);

    expect(uploads, isEmpty);
    expect(
      find.text(Errors.message(error, 'upload your photos')),
      findsOneWidget,
    );
  });

  testWidgets('several devices ask, starting where the sheet is told to', (
    tester,
  ) async {
    final uploads = await dropPhoto(
      tester,
      () async => [device('Built-in'), device('Stick', serial: 'USB1')],
    );
    expect(uploads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('upload_target_1')));
    await tester.tap(find.byKey(const ValueKey('upload_target_confirm')));
    await tester.pumpAndSettle();

    expect(uploads, ['USB1']);
  });
}
