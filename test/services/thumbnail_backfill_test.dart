import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/utils/error_text.dart';

/// The Quark and the renderers, in memory.
class _Fake {
  final calls = <String>[];

  /// What a probe answers, by path.
  final probes = <String, ThumbnailProbe>{};
  Uint8List? rendered = Uint8List.fromList([1]);
  Object? putError;

  /// Holds each render until completed, to see how many run at once.
  final gates = <Completer<void>>[];
  bool gate = false;
  int running = 0;
  int maxRunning = 0;

  ThumbnailBackfill build({Duration budget = const Duration(seconds: 20)}) =>
      ThumbnailBackfill(
        probe: (path, {serial}) async {
          calls.add('probe $path');
          return probes[path] ??
              const ThumbnailProbe(
                served: false,
                clientRender: true,
                modTime: 't1',
              );
        },
        downloadOriginal: (path, {serial}) async {
          calls.add('download $path');
          return Uint8List.fromList([7]);
        },
        renderFromBytes: (name, bytes) => _render('bytes $name'),
        renderVideoFromUrl: (name, url) => _render('url $name ${url.path}'),
        mediaUrl: (path, {serial}) => Uri.parse('https://quark/$path'),
        putThumbnail: ({required path, serial, required thumbnail}) async {
          calls.add('put $serial:$path');
          if (putError case final e?) throw e;
        },
        budget: budget,
      );

  Future<Uint8List?> _render(String call) async {
    calls.add('render $call');
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      if (gate) {
        final g = Completer<void>();
        gates.add(g);
        await g.future;
      }
      return rendered;
    } finally {
      running--;
    }
  }
}

void main() {
  test('a HEIC is downloaded, rendered and uploaded', () async {
    final fake = _Fake();

    final filled = await fake.build().fill(path: 'a/IMG.heic', serial: 'sd1');

    expect(filled, isTrue);
    expect(fake.calls, [
      'probe a/IMG.heic',
      'download a/IMG.heic',
      'render bytes IMG.heic',
      'put sd1:a/IMG.heic',
    ]);
  });

  test('a video is rendered from its stream, never downloaded', () async {
    final fake = _Fake();

    await fake.build().fill(path: 'clips/a.mp4');

    expect(fake.calls, [
      'probe clips/a.mp4',
      'render url a.mp4 /clips/a.mp4',
      'put null:clips/a.mp4',
    ]);
  });

  test('a thumbnail the Quark already has only refreshes the tile', () async {
    final fake = _Fake()..probes['a.mp4'] = const ThumbnailProbe(served: true);

    expect(await fake.build().fill(path: 'a.mp4'), isTrue);
    expect(fake.calls, ['probe a.mp4']);
  });

  test('a plain 404 is not an invitation to render', () async {
    final fake = _Fake()..probes['a.mp4'] = const ThumbnailProbe(served: false);

    expect(await fake.build().fill(path: 'a.mp4'), isFalse);
    expect(fake.calls, ['probe a.mp4']);
  });

  test('a file that is not a video or HEIC is left alone', () async {
    final fake = _Fake();

    expect(await fake.build().fill(path: 'a.jpg'), isFalse);
    expect(fake.calls, isEmpty);
  });

  test('a version that failed is not tried again; a new one is', () async {
    final fake = _Fake()..rendered = null;
    final backfill = fake.build();

    expect(await backfill.fill(path: 'a.mp4'), isFalse);
    expect(await backfill.fill(path: 'a.mp4'), isFalse);
    expect(fake.calls.where((c) => c.startsWith('render')), hasLength(1));

    fake.probes['a.mp4'] = const ThumbnailProbe(
      served: false,
      clientRender: true,
      modTime: 't2',
    );
    await backfill.fill(path: 'a.mp4');
    expect(fake.calls.where((c) => c.startsWith('render')), hasLength(2));
  });

  test('a read-only folder is skipped after the first refusal', () async {
    final fake = _Fake()..putError = const ApiException(403);
    final backfill = fake.build();

    expect(await backfill.fill(path: 'shared/a.mp4'), isFalse);
    expect(await backfill.fill(path: 'shared/b.mp4'), isFalse);
    expect(await backfill.fill(path: 'mine/c.mp4'), isFalse);

    expect(fake.calls.where((c) => c.startsWith('probe')), [
      'probe shared/a.mp4',
      'probe mine/c.mp4',
    ]);
  });

  test('at most two render at once', () async {
    final fake = _Fake()..gate = true;
    final backfill = fake.build();

    final fills = [
      for (final name in ['a', 'b', 'c', 'd']) backfill.fill(path: '$name.mp4'),
    ];
    await pumpEventQueue();
    expect(fake.running, 2);
    while (fake.gates.any((g) => !g.isCompleted) || fake.running > 0) {
      for (final g in List.of(fake.gates)) {
        if (!g.isCompleted) g.complete();
      }
      await pumpEventQueue();
    }
    expect(await Future.wait(fills), [true, true, true, true]);
    expect(fake.maxRunning, 2);
  });

  test('a render that runs past its budget is given up', () async {
    final fake = _Fake()..gate = true;

    final filled = await fake
        .build(budget: const Duration(milliseconds: 10))
        .fill(path: 'a.mp4');

    expect(filled, isFalse);
    expect(fake.calls.where((c) => c.startsWith('put')), isEmpty);
    for (final g in fake.gates) {
      g.complete();
    }
  });

  test('a tile that went away before its turn is skipped', () async {
    final fake = _Fake()..gate = true;
    final backfill = fake.build();

    final first = backfill.fill(path: 'a.mp4');
    final second = backfill.fill(path: 'b.mp4');
    final gone = backfill.fill(path: 'c.mp4', stillWanted: () => false);
    await pumpEventQueue();
    for (final g in List.of(fake.gates)) {
      g.complete();
    }

    expect(await gone, isFalse);
    await Future.wait([first, second]);
    expect(fake.calls, isNot(contains('probe c.mp4')));
  });

  test('two tiles for one file share a single attempt', () async {
    final fake = _Fake();
    final backfill = fake.build();

    final results = await Future.wait([
      backfill.fill(path: 'a.mp4'),
      backfill.fill(path: 'a.mp4'),
    ]);

    expect(results, [true, true]);
    expect(fake.calls.where((c) => c.startsWith('probe')), hasLength(1));
  });
}
