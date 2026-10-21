import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/client_thumbnails_desktop.dart';

class _FakeSession implements DesktopVideoSession {
  _FakeSession(this.length, {this.fail = false});

  final Duration? length;
  final bool fail;
  Duration? framedAt;
  int? framedLongEdge;
  bool closed = false;

  @override
  Future<Duration?> get duration async => length;

  @override
  Future<Uint8List?> frameAt(Duration at, {required int longEdge}) async {
    framedAt = at;
    framedLongEdge = longEdge;
    if (fail) throw Exception('no decoder for this codec');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> close() async => closed = true;
}

Future<Uint8List?> _render(String name, _FakeSession session) =>
    renderDesktopVideoThumbnail(
      name: name,
      source: '/v/$name',
      open: (_) async => session,
    );

void main() {
  test(
    'a video the player decodes gets a thumbnail at the long edge',
    () async {
      final session = _FakeSession(const Duration(minutes: 1));
      expect(await _render('clip.mp4', session), Uint8List.fromList([1, 2, 3]));
      expect(session.framedLongEdge, 400);
      expect(session.closed, isTrue);
    },
  );

  test('a video the player cannot decode gets no thumbnail', () async {
    final session = _FakeSession(const Duration(minutes: 1), fail: true);
    expect(await _render('clip.mkv', session), isNull);
    expect(session.closed, isTrue);
  });

  test('a video that never opens gets no thumbnail', () async {
    final thumbnail = await renderDesktopVideoThumbnail(
      name: 'clip.mp4',
      source: '/v/clip.mp4',
      open: (_) async => throw Exception('cannot open'),
    );
    expect(thumbnail, isNull);
  });

  test('a render that hangs is given up on', () async {
    final thumbnail = await renderDesktopVideoThumbnail(
      name: 'clip.mp4',
      source: '/v/clip.mp4',
      open: (_) => Completer<DesktopVideoSession>().future,
      timeout: const Duration(milliseconds: 10),
    );
    expect(thumbnail, isNull);
  });

  test('a photo renders nothing and opens no player', () async {
    var opened = false;
    final thumbnail = await renderDesktopVideoThumbnail(
      name: 'photo.jpg',
      source: '/v/photo.jpg',
      open: (_) async {
        opened = true;
        return _FakeSession(null);
      },
    );
    expect(thumbnail, isNull);
    expect(opened, isFalse);
  });

  group('frame time', () {
    Future<Duration?> frameFor(Duration? length) async {
      final session = _FakeSession(length);
      await _render('clip.mp4', session);
      return session.framedAt;
    }

    test('is two seconds in for a video of 20 seconds or more', () async {
      expect(
        await frameFor(const Duration(seconds: 20)),
        const Duration(seconds: 2),
      );
      expect(
        await frameFor(const Duration(minutes: 5)),
        const Duration(seconds: 2),
      );
    });

    test('is a tenth of the way in under 20 seconds', () async {
      expect(
        await frameFor(const Duration(seconds: 10)),
        const Duration(seconds: 1),
      );
    });

    test('is two seconds in when the length is unknown', () async {
      expect(await frameFor(null), const Duration(seconds: 2));
    });
  });
}
