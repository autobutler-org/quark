import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart'
    show QuarkModelMesh, ThumbnailIssue;

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
        renderModelFile: (path, {serial}) => _render('model file $path'),
        renderModel: (mesh) => _render('model mesh ${mesh.triangleCount}'),
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
  group('a 3D model (#3227)', () {
    test('is read and rendered from its file when a tile asks', () async {
      final fake = _Fake();

      final filled = await fake.build().fill(path: 'p/part.stl');

      expect(filled, isTrue);
      expect(fake.calls, [
        'probe p/part.stl',
        'render model file p/part.stl',
        'put null:p/part.stl',
      ]);
    });

    test(
      'opened in the viewer is drawn from its mesh, not read again',
      () async {
        final fake = _Fake();
        final mesh = QuarkModelMesh.fromTriangles(
          positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          indices: Uint32List.fromList([0, 1, 2]),
        );

        final filled = await fake.build().fill(path: 'p/part.ply', mesh: mesh);

        expect(filled, isTrue);
        expect(fake.calls, [
          'probe p/part.ply',
          'render model mesh 1',
          'put null:p/part.ply',
        ]);
      },
    );

    test(
      'that renders nothing keeps its icon and is not tried again',
      () async {
        final fake = _Fake()..rendered = null;
        final backfill = fake.build();

        expect(await backfill.fill(path: 'p/huge.obj'), isFalse);
        expect(backfill.failureFor('p/huge.obj'), isNull);
        expect(await backfill.fill(path: 'p/huge.obj'), isFalse);
        expect(fake.calls.where((c) => c.startsWith('render')), hasLength(1));
      },
    );

    test('that the Quark already has a thumbnail for is left alone', () async {
      final fake = _Fake()
        ..probes['p/part.stl'] = const ThumbnailProbe(served: true);

      expect(await fake.build().fill(path: 'p/part.stl'), isTrue);
      expect(fake.calls, ['probe p/part.stl']);
    });
  });

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

  group('a render that fails is recorded for the file (#3559)', () {
    ThumbnailProbe said(String reason) => ThumbnailProbe(
      served: false,
      clientRender: true,
      modTime: 't1',
      reason: reason,
    );

    test('a format this device cannot decode', () async {
      final fake = _Fake()
        ..rendered = null
        ..probes['a/hevc.mov'] = said('unsupported');
      final backfill = fake.build();

      expect(await backfill.fill(path: 'a/hevc.mov', serial: 'sd1'), isFalse);
      expect(
        backfill.failureFor('a/hevc.mov', serial: 'sd1'),
        ThumbnailIssue.unsupportedFormat,
      );
      expect(backfill.failureFor('a/hevc.mov'), isNull, reason: 'by device');
    });

    test('with no word from the Quark, it is the format', () async {
      final fake = _Fake()..rendered = null;
      final backfill = fake.build();

      await backfill.fill(path: 'a.ts');
      expect(backfill.failureFor('a.ts'), ThumbnailIssue.unsupportedFormat);
    });

    test('a file the Quark could not read either', () async {
      final fake = _Fake()
        ..rendered = null
        ..probes['truncated.mp4'] = said('unreadable');
      final backfill = fake.build();

      await backfill.fill(path: 'truncated.mp4');
      expect(backfill.failureFor('truncated.mp4'), ThumbnailIssue.unreadable);
    });

    test('a render that throws or runs out of time', () async {
      final fake = _Fake()
        ..gate = true
        ..probes['slow.mov'] = said('unsupported');
      final backfill = fake.build(budget: const Duration(milliseconds: 10));

      await backfill.fill(path: 'slow.mov');
      expect(backfill.failureFor('slow.mov'), ThumbnailIssue.unsupportedFormat);
      for (final g in fake.gates) {
        g.complete();
      }
    });

    test('is kept when the tile asks again, and not rendered again', () async {
      final fake = _Fake()..rendered = null;
      final backfill = fake.build();

      await backfill.fill(path: 'a.mov');
      await backfill.fill(path: 'a.mov');
      expect(fake.calls.where((c) => c.startsWith('render')), hasLength(1));
      expect(backfill.failureFor('a.mov'), ThumbnailIssue.unsupportedFormat);
    });

    test('is cleared once a new version renders', () async {
      final fake = _Fake()..rendered = null;
      final backfill = fake.build();
      await backfill.fill(path: 'a.mov');

      fake
        ..rendered = Uint8List.fromList([1])
        ..probes['a.mov'] = const ThumbnailProbe(
          served: false,
          clientRender: true,
          modTime: 't2',
        );
      expect(await backfill.fill(path: 'a.mov'), isTrue);
      expect(backfill.failureFor('a.mov'), isNull);
    });

    test('an upload the Quark refused is not a failed render', () async {
      final fake = _Fake()..putError = const ApiException(403);
      final backfill = fake.build();

      await backfill.fill(path: 'shared/a.mov');
      expect(backfill.failureFor('shared/a.mov'), isNull);
    });

    test('a plain 404 records nothing', () async {
      final fake = _Fake()
        ..probes['a.mp4'] = const ThumbnailProbe(served: false);
      final backfill = fake.build();

      await backfill.fill(path: 'a.mp4');
      expect(backfill.failureFor('a.mp4'), isNull);
    });
  });
}
