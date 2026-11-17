import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/photo_jpeg_download.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_viewer_actions.dart';

Future<void> _pumpAndDownload(
  WidgetTester tester,
  Future<String?> Function(String path, {String? serial, String? fileName})
  save,
) async {
  saveViewedFile = save;
  addTearDown(() => saveViewedFile = FilesService.saveFile);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => downloadViewedFile(
              context,
              path: 'a/b.txt',
              serial: null,
              name: 'b.txt',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump();
}

/// The Download action's snack bar: a canceled save says nothing (#3160).
void main() {
  testWidgets('a canceled save shows no message', (tester) async {
    await _pumpAndDownload(tester, (path, {serial, fileName}) async => null);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a completed save reports the download', (tester) async {
    await _pumpAndDownload(
      tester,
      (path, {serial, fileName}) async => '/home/me/b.txt',
    );
    expect(find.text('Downloaded b.txt'), findsOneWidget);
  });

  testWidgets('a failed save reports an error, not the download', (
    tester,
  ) async {
    await _pumpAndDownload(
      tester,
      (path, {serial, fileName}) async => throw Exception('boom'),
    );
    expect(find.textContaining('Downloaded'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  group('Download as JPEG (#4188)', () {
    Future<void> pumpAndConvert(
      WidgetTester tester,
      Future<PhotoJpegDownload> Function() save,
    ) async {
      savePhotoAsJpeg = ({required path, required serial, required name}) =>
          save();
      addTearDown(() => savePhotoAsJpeg = downloadPhotoAsJpeg);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => downloadViewedPhotoAsJpeg(
                  context,
                  path: 'IMG_0001.HEIC',
                  serial: null,
                  name: 'IMG_0001.HEIC',
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('reports the JPEG it saved', (tester) async {
      await pumpAndConvert(
        tester,
        () async => (
          savedAt: '/d/IMG_0001.jpg',
          fileName: 'IMG_0001.jpg',
          converted: true,
        ),
      );
      expect(find.text('Downloaded IMG_0001.jpg'), findsOneWidget);
    });

    testWidgets('says why when the original was saved instead', (tester) async {
      await pumpAndConvert(
        tester,
        () async => (
          savedAt: '/d/IMG_0001.HEIC',
          fileName: 'IMG_0001.HEIC',
          converted: false,
        ),
      );
      expect(
        find.text(Errors.jpegConversionUnavailable('IMG_0001.HEIC')),
        findsOneWidget,
      );
    });

    testWidgets('a canceled save shows no message', (tester) async {
      await pumpAndConvert(
        tester,
        () async => (savedAt: null, fileName: 'IMG_0001.jpg', converted: true),
      );
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
