import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:video_player/video_player.dart';

/// Music played behind a slideshow (#4179): a list of tracks, one after
/// another and round again, until [stop].
abstract interface class SlideshowMusic {
  /// Plays [tracks] in order from the first, looping, in place of anything
  /// playing.
  Future<void> play(List<Uri> tracks);

  /// Pauses the track playing.
  Future<void> pause();

  /// Resumes a paused track.
  Future<void> resume();

  /// Stops and lets go of the player.
  Future<void> stop();
}

/// [SlideshowMusic] through `video_player`, the player the audio viewer uses,
/// so it plays wherever audio files do. Like that viewer, it routes a
/// local-network Quark through [LocalMediaProxy], whose self-signed
/// certificate the native player would refuse.
class VideoPlayerSlideshowMusic implements SlideshowMusic {
  VideoPlayerController? _player;
  LocalMediaProxy? _proxy;
  List<Uri> _tracks = const [];
  int _track = 0;
  bool _paused = false;

  /// Tracks in a row that failed to open.
  int _failures = 0;

  /// Bumped by every [play] and [stop], so a track that finishes opening
  /// after the music moved on is dropped.
  int _session = 0;

  @override
  Future<void> play(List<Uri> tracks) async {
    await stop();
    _tracks = tracks;
    _track = 0;
    _paused = false;
    if (tracks.isNotEmpty) await _open(_session);
  }

  Future<void> _open(int session) async {
    final url = _tracks[_track];
    LocalMediaProxy? proxy;
    VideoPlayerController? player;
    try {
      if (mediaNeedsLocalProxy(url)) proxy = await LocalMediaProxy.start(url);
      player = VideoPlayerController.networkUrl(proxy?.localUrl ?? url);
      await player.initialize();
    } catch (e) {
      // A track that will not play is skipped rather than ending the music.
      debugPrint('[slideshow_music_player.dart] open error: $e');
      await player?.dispose();
      await proxy?.close();
      if (session == _session && _tracks.length > 1) _skipAfterFailure(session);
      return;
    }
    if (session != _session) {
      await player.dispose();
      await proxy?.close();
      return;
    }
    _player = player;
    _proxy = proxy;
    player.addListener(() => _onTick(player!, session));
    if (!_paused) await player.play();
  }

  /// Moves on to the next track, unless every track has failed in a row,
  /// so a list where nothing plays does not spin.
  void _skipAfterFailure(int session) {
    if (++_failures >= _tracks.length) return;
    _track = (_track + 1) % _tracks.length;
    unawaited(_open(session));
  }

  void _onTick(VideoPlayerController player, int session) {
    final value = player.value;
    final ended =
        value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration;
    if (!ended || session != _session || player != _player) return;
    _failures = 0;
    unawaited(_next(session));
  }

  Future<void> _next(int session) async {
    await _release();
    if (session != _session) return;
    _track = (_track + 1) % _tracks.length;
    await _open(session);
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    await _player?.play();
  }

  @override
  Future<void> stop() async {
    _session++;
    _failures = 0;
    await _release();
  }

  Future<void> _release() async {
    final player = _player;
    final proxy = _proxy;
    _player = null;
    _proxy = null;
    await player?.dispose();
    await proxy?.close();
  }
}
