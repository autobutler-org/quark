import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A [VideoPlayerPlatform] that initializes every player at once and can
/// reject play() the way a browser does when autoplay is blocked.
///
/// video_player_web reports that rejection on the event stream rather than by
/// throwing from play(), so [rejectPlay] does the same.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({this.rejectPlay = false});

  /// Whether play() fails with the browser's autoplay error.
  final bool rejectPlay;

  /// How many times the controller reached the platform's play().
  int playCalls = 0;

  final StreamController<VideoEvent> _events = StreamController<VideoEvent>();

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    _events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(640, 360),
      ),
    );
    return _events.stream;
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
    if (rejectPlay) {
      _events.addError(
        PlatformException(
          code: 'NotAllowedError',
          message: "play() failed because the user didn't interact first",
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
