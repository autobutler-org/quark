// cspell:words galadriel prores
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/fake_thumbnail_store.dart';

/// #3559: a video whose thumbnail no one could make showed the same generic
/// icon as a file with no thumbnail at all, and said nothing about why.
void main() {
  // Set, never read: reading builds the real store, which needs a platform
  // channel. Each test file runs in its own isolate.
  setUpAll(
    () =>
        ThumbnailCacheManager
            .instance = // A Quark with no thumbnail for any file: every load is a 404.
        FakeThumbnailStore(
          (url) => throw HttpExceptionWithStatus(
            404,
            'missing',
            uri: Uri.parse(url),
          ),
        ),
  );

  FileNode video(String name) => FileNode(
    name: name,
    size: 128,
    isDir: false,
    deviceName: 'Quark',
    devicePath: '',
    deviceSerial: '',
    dirPath: 'users/galadriel/$name',
  );

  /// The Quark answers 404 with clientRender and [reason], and this browser
  /// cannot decode the video either: its render comes back empty once [gate]
  /// opens.
  ThumbnailBackfill backfill(String reason, {Completer<void>? gate}) =>
      ThumbnailBackfill(
        probe: (path, {serial}) async => ThumbnailProbe(
          served: false,
          clientRender: true,
          modTime: 't',
          reason: reason,
        ),
        renderVideoFromUrl: (name, url) async {
          await gate?.future;
          return null;
        },
        mediaUrl: (path, {serial}) => Uri.parse('https://quark/$path'),
        putThumbnail: ({required path, serial, required thumbnail}) async {},
      );

  /// Pumps [widget] until its thumbnail load has failed and the backfill has
  /// answered.
  Future<void> settle(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox.square(dimension: 160, child: widget)),
        ),
      ),
    );
    // The image load runs on real futures; the backfill on fake ones.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final (label, build) in [
    (
      'list row',
      (FileNode item, ThumbnailBackfill b) =>
          FileListLeading(item: item, backfill: b),
    ),
    (
      'grid tile',
      (FileNode item, ThumbnailBackfill b) =>
          FileGridPreview(item: item, backfill: b),
    ),
  ]) {
    testWidgets('a $label for a format this device cannot preview says so', (
      tester,
    ) async {
      await settle(
        tester,
        build(video('hevc-aac.mov'), backfill('unsupported')),
      );

      final placeholder = tester.widget<QuarkThumbnailUnavailable>(
        find.byType(QuarkThumbnailUnavailable),
      );
      expect(placeholder.issue, ThumbnailIssue.unsupportedFormat);
      expect(
        placeholder.reason,
        Errors.thumbnailUnavailable(
          ThumbnailIssue.unsupportedFormat,
          isVideo: true,
        ),
      );
      expect(find.byIcon(QuarkIcons.video_file_outlined), findsOneWidget);
      expect(
        find.byIcon(QuarkIcons.insert_drive_file_outlined),
        findsNothing,
        reason: 'not the generic file icon',
      );
      await unmount(tester);
    });

    testWidgets('a $label for a file that could not be read says so', (
      tester,
    ) async {
      await settle(
        tester,
        build(video('truncated.mp4'), backfill('unreadable')),
      );

      final placeholder = tester.widget<QuarkThumbnailUnavailable>(
        find.byType(QuarkThumbnailUnavailable),
      );
      expect(placeholder.issue, ThumbnailIssue.unreadable);
      expect(
        placeholder.reason,
        Errors.thumbnailUnavailable(ThumbnailIssue.unreadable, isVideo: true),
      );
      await unmount(tester);
    });

    testWidgets('a $label still rendering shows neither', (tester) async {
      final gate = Completer<void>();
      await settle(
        tester,
        build(video('h264-aac.ts'), backfill('unsupported', gate: gate)),
      );

      expect(find.byType(QuarkThumbnailUnavailable), findsNothing);
      gate.complete();
      await unmount(tester);
    });
  }

  testWidgets('the grid tile writes the short reason where a finger sees it', (
    tester,
  ) async {
    await settle(
      tester,
      FileGridPreview(item: video('prores-pcm.mov'), backfill: backfill('')),
    );

    expect(
      find.text(
        Errors.thumbnailUnavailableShort(ThumbnailIssue.unsupportedFormat),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });
}
