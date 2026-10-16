import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';

/// Serves one PNG for every thumbnail and counts the fetches.
class _FakeThumbnailStore extends Fake implements BaseCacheManager {
  _FakeThumbnailStore(this.png);

  final Uint8List png;
  final _files = MemoryCacheSystem();
  var fetches = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    fetches++;
    final file = await _files.createFile(Uri.parse(url).pathSegments.last);
    await file.writeAsBytes(png);
    yield FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 1)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {}
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// #3366: a photo tile scrolled away and back, while its decoded picture is
/// still in the image cache, shows that picture again.
///
/// It used to be decoded a second time: cached_network_image's completer
/// asks its codec for another frame whenever a listener returns, and the new
/// frame replaces the one the tile had. On the web both frames are drawn from
/// the same `<img>` element, and dropping the first clears that element's
/// `src`, so the second painted nothing but black ("texImage2D: no image").
void main() {
  tearDown(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  ui.Image? shown(WidgetTester tester) {
    final raw = find.byType(RawImage);
    return raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
  }

  testWidgets('a tile shown again reuses its decoded picture', (tester) async {
    final png = (await tester.runAsync(_png))!;
    final store = _FakeThumbnailStore(png);
    ThumbnailCacheManager.instance = store;
    final tile = MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 100,
          child: PhotoThumbnail(
            url: Uri.parse('http://quark.local/api/v0/thumbnails/a.png'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(tile);
    await settle(tester);
    expect(shown(tester), isNotNull);

    // Scrolled away: the tile is disposed, its picture stays in the cache.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(tile);
    final cached = shown(tester);
    expect(cached, isNotNull, reason: 'the cached picture is not shown');
    await settle(tester);

    final again = shown(tester);
    expect(again, isNotNull, reason: 'the tile paints no picture');
    expect(again!.debugDisposed, isFalse);
    expect(
      identical(again, cached),
      isTrue,
      reason: 'the picture was decoded again and replaced the cached one',
    );
    expect(store.fetches, 1);
    expect(tester.takeException(), isNull);
  });
}
