import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/desktop_thumbnail_renderer.dart';

class _FakeCodecs {
  final calls = <String>[];
  Duration? duration = const Duration(minutes: 1);
  bool fail = false;
  Completer<void>? hang;

  DesktopThumbnailCodecs build() => DesktopThumbnailCodecs(
    videoDuration: (source) async {
      calls.add('duration $source');
      return duration;
    },
    videoFrame: (source, {required longEdge, required at}) async {
      calls.add('frame $source $longEdge ${at.inMilliseconds}');
      await hang?.future;
      if (fail) throw Exception('no decoder');
      return Uint8List.fromList([1, 2, 3]);
    },
  );
}

void main() {
  test('a long video is framed two seconds in at the long edge', () async {
    final fake = _FakeCodecs();
    final thumbnail = await renderDesktopVideoThumbnail(
      name: 'a.mp4',
      source: '/v/a.mp4',
      codecs: fake.build(),
    );
    expect(thumbnail, [1, 2, 3]);
    expect(fake.calls, ['duration /v/a.mp4', 'frame /v/a.mp4 400 2000']);
  });

  test('a short video is framed a tenth of the way in', () async {
    final fake = _FakeCodecs()..duration = const Duration(seconds: 10);
    await renderDesktopVideoThumbnail(
      name: 'a.mov',
      source: '/v/a.mov',
      codecs: fake.build(),
    );
    expect(fake.calls.last, 'frame /v/a.mov 400 1000');
  });

  test('an unknown length falls back to two seconds', () async {
    final fake = _FakeCodecs()..duration = null;
    await renderDesktopVideoThumbnail(
      name: 'a.mp4',
      source: '/v/a.mp4',
      codecs: fake.build(),
    );
    expect(fake.calls.last, 'frame /v/a.mp4 400 2000');
  });

  test('a photo renders nothing', () async {
    final fake = _FakeCodecs();
    expect(
      await renderDesktopVideoThumbnail(
        name: 'a.jpg',
        source: '/v/a.jpg',
        codecs: fake.build(),
      ),
      isNull,
    );
    expect(fake.calls, isEmpty);
  });

  test('a decoder failure returns null instead of throwing', () async {
    final fake = _FakeCodecs()..fail = true;
    expect(
      await renderDesktopVideoThumbnail(
        name: 'a.mp4',
        source: '/v/a.mp4',
        codecs: fake.build(),
      ),
      isNull,
    );
  });

  test('a render that hangs is given up on after the timeout', () async {
    final fake = _FakeCodecs()..hang = Completer<void>();
    expect(
      await renderDesktopVideoThumbnail(
        name: 'a.mp4',
        source: '/v/a.mp4',
        codecs: fake.build(),
        timeout: const Duration(milliseconds: 10),
      ),
      isNull,
    );
  });
}
