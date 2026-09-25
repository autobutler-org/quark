import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
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
}
