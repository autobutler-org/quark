import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';

void main() {
  /// A backfill whose Quark says to render, and whose render succeeds.
  ThumbnailBackfill backfill(List<String> probes) => ThumbnailBackfill(
    probe: (path, {serial}) async {
      probes.add(path);
      return const ThumbnailProbe(
        served: false,
        clientRender: true,
        modTime: 't',
      );
    },
    renderVideoFromUrl: (name, url) async => Uint8List.fromList([1]),
    mediaUrl: (path, {serial}) => Uri.parse('https://quark/$path'),
    putThumbnail: ({required path, serial, required thumbnail}) async {},
  );

  testWidgets('a failed load is backfilled once, then built again', (
    tester,
  ) async {
    final probes = <String>[];
    final generations = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BackfillingThumbnail(
          path: 'clips/a.mp4',
          backfill: backfill(probes),
          builder: (context, generation, onFailed) {
            generations.add(generation);
            // Every build fails, as a thumbnail the Quark lacks does.
            onFailed();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(probes, ['clips/a.mp4'], reason: 'asked once, not once per build');
    expect(generations.last, 1, reason: 'rebuilt to load the new thumbnail');
  });

  testWidgets('a tile gone before its backfill lands is left alone', (
    tester,
  ) async {
    final gate = Completer<void>();
    final slow = ThumbnailBackfill(
      probe: (path, {serial}) async {
        await gate.future;
        return const ThumbnailProbe(served: true);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BackfillingThumbnail(
          path: 'clips/a.mp4',
          backfill: slow,
          builder: (context, generation, onFailed) {
            onFailed();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();

    // No setState after dispose, which would have thrown.
    expect(tester.takeException(), isNull);
  });

  /// #3349: a Quark too busy to serve a thumbnail answers 503, and the tile
  /// used to sit on its placeholder until it was scrolled away and back.
  group('a busy Quark', () {
    HttpExceptionWithStatus busy(int status) =>
        HttpExceptionWithStatus(status, 'busy', uri: Uri.parse('https://q/t'));

    Future<List<int>> pumpFailing(
      WidgetTester tester,
      Object Function(int generation) error, {
      List<String>? probes,
    }) async {
      final generations = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BackfillingThumbnail(
            path: 'clips/a.mp4',
            backfill: backfill(probes ?? []),
            builder: (context, generation, onFailed) {
              generations.add(generation);
              onFailed(error(generation));
              return const SizedBox();
            },
          ),
        ),
      );
      return generations;
    }

    for (final status in [429, 502, 503, 504]) {
      testWidgets('is asked again after a $status', (tester) async {
        final generations = await pumpFailing(tester, (_) => busy(status));
        expect(generations, [0]);

        await tester.pump(ThumbnailCacheConfig.busyRetryDelay);
        expect(generations, [0, 1]);
      });
    }

    testWidgets('is asked a few times, backing off, then left alone', (
      tester,
    ) async {
      final generations = await pumpFailing(tester, (_) => busy(503));
      var delay = ThumbnailCacheConfig.busyRetryDelay;
      for (var i = 1; i <= ThumbnailCacheConfig.busyRetries; i++) {
        await tester.pump(delay - const Duration(milliseconds: 1));
        expect(generations.last, i - 1, reason: 'not before its delay');
        await tester.pump(const Duration(milliseconds: 1));
        expect(generations.last, i);
        delay *= 2;
      }
      await tester.pump(delay * 4);
      expect(generations.last, ThumbnailCacheConfig.busyRetries);
    });

    testWidgets('is retried, and a missing thumbnail after it is backfilled', (
      tester,
    ) async {
      final probes = <String>[];
      final generations = await pumpFailing(
        tester,
        (generation) => generation == 0 ? busy(503) : busy(404),
        probes: probes,
      );
      await tester.pump(ThumbnailCacheConfig.busyRetryDelay);
      await tester.pump(ThumbnailCacheConfig.busyRetryDelay * 8);

      // 1 is the retry after the 503; 2 the reload after the 404's backfill.
      expect(generations, [0, 1, 2]);
      expect(probes, ['clips/a.mp4'], reason: 'only the 404 asks to backfill');
    });

    testWidgets('a tile gone before its retry is left alone', (tester) async {
      await pumpFailing(tester, (_) => busy(503));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(ThumbnailCacheConfig.busyRetryDelay);

      expect(tester.takeException(), isNull);
    });
  });
}
