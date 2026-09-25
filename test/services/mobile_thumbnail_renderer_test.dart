import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/mobile_thumbnail_renderer.dart';

/// A JPEG the fake codecs "encode": its bytes are just a label, and
/// [_FakeCodecs.sizes] says what size it is.
Uint8List _jpeg(String label) => Uint8List.fromList(label.codeUnits);

String _label(Uint8List? bytes) =>
    bytes == null ? 'null' : String.fromCharCodes(bytes);

class _FakeCodecs {
  final calls = <String>[];

  /// The size of each encoded output, by label.
  final sizes = <String, ({int width, int height})>{};

  ({int width, int height})? sourceSize;
  Duration? duration = const Duration(minutes: 1);
  bool failVideo = false;
  Completer<void>? hang;

  MobileThumbnailCodecs build() => MobileThumbnailCodecs(
    videoFrame: (path, {required longEdge, required at}) async {
      calls.add('frame $path $longEdge ${at.inMilliseconds}');
      await hang?.future;
      if (failVideo) throw Exception('no decoder');
      return _jpeg('frame$longEdge');
    },
    videoDuration: (path) async {
      calls.add('duration $path');
      return duration;
    },
    sourceSizeOfFile: (path) async => sourceSize,
    sizeOfBytes: (bytes) async => sizes[_label(bytes)] ?? sourceSize,
    compressFile: (path, {required shortEdge}) async {
      calls.add('file $path $shortEdge');
      return _jpeg('file$shortEdge');
    },
    compressBytes: (bytes, {required shortEdge}) async {
      calls.add('bytes ${_label(bytes)} $shortEdge');
      return _jpeg('bytes$shortEdge');
    },
  );
}

void main() {
  group('photos', () {
    test('a JPEG gets a thumbnail sized from its long edge', () async {
      final fake = _FakeCodecs()
        ..sourceSize = (width: 4032, height: 3024)
        ..sizes['file300'] = (width: 400, height: 300);

      final thumbnail = await renderMobileThumbnail(
        name: 'IMG_1.jpg',
        path: '/p/IMG_1.jpg',
        codecs: fake.build(),
      );

      // Short edge 300 is what makes the plugin land the long edge on 400.
      expect(fake.calls, ['file /p/IMG_1.jpg 300']);
      expect(_label(thumbnail), 'file300');
    });

    test('a HEIC goes through the same encoder, one thumbnail only', () async {
      final fake = _FakeCodecs()
        ..sourceSize = (width: 3024, height: 4032)
        ..sizes['file300'] = (width: 300, height: 400);

      final thumbnail = await renderMobileThumbnail(
        name: 'IMG_1.HEIC',
        path: '/p/IMG_1.HEIC',
        codecs: fake.build(),
      );

      expect(fake.calls, ['file /p/IMG_1.HEIC 300']);
      expect(_label(thumbnail), 'file300');
    });

    test('a photo smaller than the target is never enlarged', () async {
      final fake = _FakeCodecs()..sourceSize = (width: 320, height: 240);

      await renderMobileThumbnail(
        name: 'small.png',
        path: '/p/small.png',
        codecs: fake.build(),
      );

      expect(fake.calls, ['file /p/small.png 240']);
    });

    test('a source it cannot measure is shrunk again once encoded', () async {
      // No size up front: the first pass takes the short edge to 400, and
      // the encoded JPEG, which it can always measure, is brought down to a
      // 400 long edge.
      final fake = _FakeCodecs()..sizes['file400'] = (width: 1600, height: 400);

      final thumbnail = await renderMobileThumbnail(
        name: 'pano.heic',
        path: '/p/pano.heic',
        codecs: fake.build(),
      );

      expect(fake.calls, ['file /p/pano.heic 400', 'bytes file400 100']);
      expect(_label(thumbnail), 'bytes100');
    });

    test('a photo that is only bytes goes through the bytes encoder', () async {
      final fake = _FakeCodecs()
        ..sourceSize = (width: 800, height: 600)
        ..sizes['bytes300'] = (width: 400, height: 300);

      final thumbnail = await renderMobileThumbnail(
        name: 'a.jpg',
        bytes: _jpeg('source'),
        codecs: fake.build(),
      );

      expect(fake.calls, ['bytes source 300']);
      expect(_label(thumbnail), 'bytes300');
    });
  });

  group('videos', () {
    test('a long video is framed two seconds in, one thumbnail', () async {
      final fake = _FakeCodecs();

      final thumbnail = await renderMobileThumbnail(
        name: 'clip.MOV',
        path: '/p/clip.MOV',
        codecs: fake.build(),
      );

      expect(fake.calls, [
        'duration /p/clip.MOV',
        'frame /p/clip.MOV 400 2000',
      ]);
      expect(_label(thumbnail), 'frame400');
    });

    test('a short clip is framed a tenth of the way in', () async {
      final fake = _FakeCodecs()..duration = const Duration(seconds: 5);

      await renderMobileThumbnail(
        name: 'clip.mp4',
        path: '/p/clip.mp4',
        codecs: fake.build(),
      );

      expect(fake.calls.last, 'frame /p/clip.mp4 400 500');
    });

    test('an unknown length falls back to two seconds', () async {
      final fake = _FakeCodecs()..duration = null;

      await renderMobileThumbnail(
        name: 'clip.mp4',
        path: '/p/clip.mp4',
        codecs: fake.build(),
      );

      expect(fake.calls.last, 'frame /p/clip.mp4 400 2000');
    });

    test('a video that is only bytes renders nothing', () async {
      final fake = _FakeCodecs();

      final thumbnail = await renderMobileThumbnail(
        name: 'clip.mp4',
        bytes: _jpeg('video'),
        codecs: fake.build(),
      );

      expect(thumbnail, isNull);
      expect(fake.calls, isEmpty);
    });
  });

  test('a document renders nothing', () async {
    final fake = _FakeCodecs();
    expect(
      await renderMobileThumbnail(
        name: 'notes.txt',
        path: '/p/notes.txt',
        codecs: fake.build(),
      ),
      isNull,
    );
    expect(fake.calls, isEmpty);
  });

  test('a failure is nothing rendered, not an error', () async {
    final fake = _FakeCodecs()..failVideo = true;

    final thumbnail = await renderMobileThumbnail(
      name: 'clip.mp4',
      path: '/p/clip.mp4',
      codecs: fake.build(),
    );

    expect(thumbnail, isNull);
  });

  test('a render that runs out of time is nothing rendered', () async {
    final fake = _FakeCodecs()..hang = Completer<void>();

    final thumbnail = await renderMobileThumbnail(
      name: 'clip.mp4',
      path: '/p/clip.mp4',
      codecs: fake.build(),
      timeout: const Duration(milliseconds: 10),
    );

    expect(thumbnail, isNull);
    fake.hang!.complete();
  });
}
