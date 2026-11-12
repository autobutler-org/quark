// cspell:words hevc prores unopenable
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/playback_position.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// How the fake player answers [VideoViewerPage] for one file.
class _Outcome {
  const _Outcome.ready()
    : duration = const Duration(seconds: 10),
      size = const Size(640, 360),
      failInitialize = false,
      errorOnPlay = false;

  /// The browser rejects the file before a player exists.
  const _Outcome.unopenable()
    : duration = Duration.zero,
      size = Size.zero,
      failInitialize = true,
      errorOnPlay = false;

  /// The browser reports a player with no decoded picture.
  const _Outcome.noPicture({this.duration = const Duration(seconds: 2)})
    : size = Size.zero,
      failInitialize = false,
      errorOnPlay = false;

  /// The browser reports a real picture, then a decode error on play.
  const _Outcome.errorOnPlay()
    : duration = const Duration(seconds: 2),
      size = const Size(640, 360),
      failInitialize = false,
      errorOnPlay = true;

  final Duration duration;
  final Size size;
  final bool failInitialize;
  final bool errorOnPlay;
}

/// A [VideoPlayerPlatform] whose one player follows an [_Outcome].
class _OutcomePlatform extends VideoPlayerPlatform {
  _OutcomePlatform(this.outcome);

  final _Outcome outcome;
  final StreamController<VideoEvent> _events = StreamController<VideoEvent>();

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (outcome.failInitialize) {
      _events.addError(
        PlatformException(
          code: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
          message: 'The video has been found to be unsuitable',
        ),
      );
    } else {
      _events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: outcome.duration,
          size: outcome.size,
        ),
      );
    }
    return _events.stream;
  }

  @override
  Future<void> play(int playerId) async {
    if (outcome.errorOnPlay) {
      _events.addError(
        PlatformException(
          code: 'MEDIA_ERR_DECODE',
          message: 'An error occurred while trying to decode the video',
        ),
      );
    }
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

/// One file the viewer must not leave the user with a dead action or a black
/// player (#3429).
class _Clip {
  const _Clip({
    required this.fileName,
    required this.outcome,
    required this.playbackMessage,
    this.forbidsCodecWord = false,
    this.expectsDownload = false,
    this.autoplay = false,
  });

  final String fileName;
  final _Outcome outcome;
  final String playbackMessage;
  final bool forbidsCodecWord;
  final bool expectsDownload;
  final bool autoplay;
}

void main() {
  Future<PlaybackPosition> noPosition(
    String relPath, {
    String? serial,
    Duration? position,
    Duration? duration,
    bool? watched,
  }) async => const PlaybackPosition();

  Future<void> pumpClip(WidgetTester tester, _Clip clip) async {
    VideoPlayerPlatform.instance = _OutcomePlatform(clip.outcome);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoViewerPage(
          url: Uri.http('quark.test', '/api/v0/files/download', {
            'filePath': 'Movies/${clip.fileName}',
            'serial': 'USB1',
          }),
          name: clip.fileName,
          canAutoplay: () => clip.autoplay,
          loadPlayback: (relPath, {serial}) => noPosition(relPath),
          savePlayback:
              (relPath, {serial, required position, required duration}) =>
                  noPosition(relPath),
          setPlaybackWatched: (relPath, {serial, required watched}) =>
              noPosition(relPath, watched: watched),
          loadTranscodeFormats: (relPath, {serial}) async =>
              const <TranscodeFormat>[],
          transcodeVideo: (relPath, {serial, required format}) async => 0,
        ),
      ),
    );
    // Bounded pumps: a playing progress bar never settles.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('video_viewer_more')));
    // The menu fades its items in; a second pump lands them where a tap hits.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// MenuItemButton runs its action after the frame that closed the menu, and
  /// that action's setState shows up on the frame after that.
  Future<void> tapMenuItem(WidgetTester tester, Key key) async {
    await openMenu(tester);
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump();
  }

  /// A snack bar stays up for seconds and queues the next one behind it, so a
  /// later action's message is invisible until this one is gone.
  void clearSnackBars(WidgetTester tester) {
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).removeCurrentSnackBar();
  }

  testWidgets('a playable clip opens the trim bar', (tester) async {
    await pumpClip(
      tester,
      const _Clip(
        fileName: 'clip.mp4',
        outcome: _Outcome.ready(),
        playbackMessage: '',
      ),
    );

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.text(Errors.unsupportedVideoCodec), findsNothing);
    expect(find.text('Save Clip'), findsNothing);

    await tapMenuItem(tester, const ValueKey('video_viewer_trim'));

    expect(find.text('Save Clip'), findsOneWidget);
    expect(find.text(Errors.trimUnavailable), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  // #3424: a TS file the player opens still can't be cut on the Quark, so
  // Trim says why instead of opening a bar whose Save Clip is refused.
  testWidgets('a playable TS clip explains it cannot be trimmed', (
    tester,
  ) async {
    await pumpClip(
      tester,
      const _Clip(
        fileName: 'h264-aac.ts',
        outcome: _Outcome.ready(),
        playbackMessage: '',
      ),
    );

    expect(find.byType(VideoPlayer), findsOneWidget);

    await tapMenuItem(tester, const ValueKey('video_viewer_trim'));

    expect(find.text(Errors.cantTrimContainer('.TS')), findsOneWidget);
    expect(find.text('Save Clip'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  final unplayable = <_Clip>[
    _Clip(
      fileName: 'clip.avi',
      outcome: const _Outcome.unopenable(),
      playbackMessage: Errors.unsupportedVideoFormat('.AVI'),
      expectsDownload: true,
    ),
    _Clip(
      fileName: 'clip.ts',
      outcome: const _Outcome.unopenable(),
      playbackMessage: Errors.unsupportedVideoContainer('.TS'),
      forbidsCodecWord: true,
      expectsDownload: true,
    ),
    const _Clip(
      fileName: 'truncated.mp4',
      outcome: _Outcome.unopenable(),
      playbackMessage: Errors.unplayableMedia,
    ),
    const _Clip(
      fileName: 'notes.txt',
      outcome: _Outcome.unopenable(),
      playbackMessage: Errors.unplayableMedia,
    ),
    _Clip(
      fileName: 'prores.mov',
      outcome: const _Outcome.noPicture(duration: Duration.zero),
      playbackMessage: Errors.unsupportedVideoCodec,
      expectsDownload: true,
    ),
    const _Clip(
      fileName: 'hevc.mov',
      outcome: _Outcome.noPicture(),
      playbackMessage: Errors.unsupportedVideoCodec,
      expectsDownload: true,
    ),
  ];

  for (final clip in unplayable) {
    testWidgets('${clip.fileName} never leaves an action doing nothing', (
      tester,
    ) async {
      await pumpClip(tester, clip);

      expect(find.text(clip.playbackMessage), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byIcon(QuarkIcons.play_arrow), findsNothing);
      expect(find.textContaining('0:00 /'), findsNothing);
      if (clip.expectsDownload) {
        expect(find.text('Download'), findsOneWidget);
      }
      if (clip.forbidsCodecWord) {
        expect(clip.playbackMessage.toLowerCase(), isNot(contains('codec')));
        expect(find.text(Errors.unplayableMedia), findsNothing);
      }

      // A TS file is refused for its container before playback is asked.
      final trimMessage = clip.fileName.endsWith('.ts')
          ? Errors.cantTrimContainer('.TS')
          : Errors.trimUnavailable;
      expect(find.text(trimMessage), findsNothing);
      await tapMenuItem(tester, const ValueKey('video_viewer_trim'));
      expect(find.text(trimMessage), findsOneWidget);
      expect(find.text('Save Clip'), findsNothing);
      clearSnackBars(tester);
      await tester.pump();

      expect(find.text(Errors.saveFrameUnavailable), findsNothing);
      await tapMenuItem(tester, const ValueKey('video_viewer_save_frame'));
      expect(find.text(Errors.saveFrameUnavailable), findsOneWidget);

      await tapMenuItem(tester, const ValueKey('video_viewer_convert'));
      await tester.pump();
      expect(find.text('Convert video'), findsOneWidget);
      expect(
        find.text('There are no formats to convert this video to.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });
  }

  // #3728: Download says it downloaded, as the other viewers do (#3160).
  testWidgets('Download reports the saved video', (tester) async {
    final saves = <(String, String?, String?)>[];
    saveViewedFile = (path, {serial, fileName}) async {
      saves.add((path, serial, fileName));
      return '/home/me/$fileName';
    };
    addTearDown(() => saveViewedFile = FilesService.saveFile);
    await pumpClip(
      tester,
      _Clip(
        fileName: 'clip.avi',
        outcome: const _Outcome.unopenable(),
        playbackMessage: Errors.unsupportedVideoFormat('.AVI'),
        expectsDownload: true,
      ),
    );

    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump();

    expect(saves, [('Movies/clip.avi', 'USB1', 'clip.avi')]);
    expect(find.text('Downloaded clip.avi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a decode error after play replaces the player', (tester) async {
    await pumpClip(
      tester,
      const _Clip(
        fileName: 'hevc.mov',
        outcome: _Outcome.errorOnPlay(),
        playbackMessage: Errors.unsupportedVideoCodec,
        expectsDownload: true,
        autoplay: true,
      ),
    );

    expect(find.text(Errors.unsupportedVideoCodec), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.textContaining('0:00 /'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
