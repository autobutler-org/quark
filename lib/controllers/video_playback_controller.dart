import 'package:flutter/foundation.dart';
import 'package:quark/models/playback_position.dart';
import 'package:quark/services/playback_position_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Reads the stored playback state of a video; see
/// [PlaybackPositionService.get].
typedef LoadPlayback =
    Future<PlaybackPosition> Function(String relPath, {String? serial});

/// Stores a playback position; see [PlaybackPositionService.save].
typedef SavePlayback =
    Future<PlaybackPosition> Function(
      String relPath, {
      String? serial,
      required Duration position,
      required Duration duration,
    });

/// Marks a video watched or unwatched; see
/// [PlaybackPositionService.setWatched].
typedef SetPlaybackWatched =
    Future<PlaybackPosition> Function(
      String relPath, {
      String? serial,
      required bool watched,
    });

/// Remembers where the signed-in user left off in one video, and whether they
/// have watched it.
///
/// It knows nothing of the player: the page feeds it positions through
/// [report] and seeks to what [load] returns. Loading and the periodic saves
/// fail silently, because a resume position is never worth interrupting
/// playback for; only [toggleWatched], which the user asked for, throws.
class VideoPlaybackController extends ChangeNotifier with SafeNotifier {
  VideoPlaybackController({
    required this.relPath,
    this.serial,
    LoadPlayback load = PlaybackPositionService.get,
    SavePlayback save = PlaybackPositionService.save,
    SetPlaybackWatched setWatched = PlaybackPositionService.setWatched,
    DateTime Function() now = DateTime.now,
  }) : _load = load,
       _save = save,
       _setWatched = setWatched,
       _now = now,
       _lastSaveAt = now();

  /// How often a playing video's position is saved.
  static const saveInterval = Duration(seconds: 10);

  /// The video's files-relative path.
  final String relPath;

  /// The serial of the device holding the video; null for the internal drive.
  final String? serial;

  final LoadPlayback _load;
  final SavePlayback _save;
  final SetPlaybackWatched _setWatched;
  final DateTime Function() _now;

  bool _watched = false;
  bool _wasPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _savedPosition;
  DateTime _lastSaveAt;

  /// Whether the video counts as watched.
  bool get watched => _watched;

  /// Fetches the stored state and returns the position to resume at: null
  /// when there is none, the video is watched, or the request failed.
  Future<Duration?> load() async {
    try {
      final state = await _load(relPath, serial: serial);
      _adopt(state);
      return state.watched || state.position <= Duration.zero
          ? null
          : state.position;
    } catch (e) {
      debugPrint('[video_playback_controller.dart] load error: $e');
      return null;
    }
  }

  /// Takes the player's current [position] and [duration]. Saves at most once
  /// every [saveInterval] while playing, and at once when playback pauses.
  Future<void> report(
    Duration position,
    Duration duration, {
    required bool isPlaying,
  }) async {
    final paused = _wasPlaying && !isPlaying;
    _wasPlaying = isPlaying;
    _position = position;
    _duration = duration;
    if (paused ||
        (isPlaying && _now().difference(_lastSaveAt) >= saveInterval)) {
      await flush();
    }
  }

  /// Saves the last reported position unless it is already saved or the
  /// video's length is unknown. Never throws.
  Future<void> flush() async {
    final position = _position;
    if (_duration <= Duration.zero || position == _savedPosition) return;
    _savedPosition = position;
    _lastSaveAt = _now();
    try {
      _adopt(
        await _save(
          relPath,
          serial: serial,
          position: position,
          duration: _duration,
        ),
      );
    } catch (e) {
      debugPrint('[video_playback_controller.dart] save error: $e');
    }
  }

  /// Marks the video unwatched when it is watched and watched when it is not.
  /// Throws what the service throws, for the page to report.
  Future<void> toggleWatched() async {
    final state = await _setWatched(
      relPath,
      serial: serial,
      watched: !_watched,
    );
    // Marking unwatched clears the stored position, so the next save has to
    // go out even from where playback already was.
    _savedPosition = null;
    _adopt(state);
  }

  void _adopt(PlaybackPosition state) {
    if (isDisposed || state.watched == _watched) return;
    _watched = state.watched;
    notifyListeners();
  }
}
