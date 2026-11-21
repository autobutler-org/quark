import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/kept_albums_config.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/photos/keep_album_dialog.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #4222: keeping an album asks previews or originals, shows the space each
/// takes before anything downloads, and waits for Wi-Fi unless told not to.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  Future<Future<KeepAlbumChoice?>> pumpDialog(
    WidgetTester tester,
    Size size,
  ) async {
    setViewport(tester, size);
    late Future<KeepAlbumChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = KeepAlbumDialog.show(
                context,
                albumName: 'A very long album name from a summer trip',
                photoCount: 100,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  String estimate({required bool originals}) =>
      'About ${StorageDevice.formatBytes(KeptAlbumsConfig.estimateBytes(100, originals: originals))} for 100 photos.';

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('it lays out and estimates previews by default ($label)', (
      tester,
    ) async {
      await pumpDialog(tester, size);

      expect(tester.takeException(), isNull);
      expect(find.text(estimate(originals: false)), findsOneWidget);
    });

    testWidgets('choosing originals raises the estimate ($label)', (
      tester,
    ) async {
      await pumpDialog(tester, size);

      await tester.tap(find.byKey(const ValueKey('keep_album_originals')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(estimate(originals: true)), findsOneWidget);
    });
  }

  testWidgets('keep answers previews over Wi-Fi only by default', (
    tester,
  ) async {
    final result = await pumpDialog(tester, wideViewport);

    await tester.tap(find.byKey(const ValueKey('keep_album_confirm')));
    await tester.pumpAndSettle();

    expect(await result, (originals: false, allowMobileData: false));
  });

  testWidgets('keep answers what was chosen', (tester) async {
    final result = await pumpDialog(tester, wideViewport);

    await tester.tap(find.byKey(const ValueKey('keep_album_originals')));
    await tester.tap(find.byKey(const ValueKey('keep_album_mobile_data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keep_album_confirm')));
    await tester.pumpAndSettle();

    expect(await result, (originals: true, allowMobileData: true));
  });

  testWidgets('cancel answers null', (tester) async {
    final result = await pumpDialog(tester, wideViewport);

    await tester.tap(find.byKey(const ValueKey('keep_album_cancel')));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
