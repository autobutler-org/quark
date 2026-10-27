import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';

/// State behind one album's page (#3283): its tracks in album order (disc,
/// then track number), and the title, artist and year read from them.
///
/// There is no single-album endpoint; the album is its tracks, fetched with
/// `albumKey`. A failed refresh keeps what it had and sets [error], and
/// `music_library_changed` or `resync` refresh after [start].
class MusicAlbumController extends ChangeNotifier {
  /// Creates the controller for [albumKey]. [listTracks] defaults to the
  /// real service and [events] to the app's event stream.
  MusicAlbumController({
    required this.albumKey,
    ListMusicTracksFn listTracks = MusicService.listTracks,
    Stream<FileEvent>? events,
  }) : _listTracks = listTracks,
       _eventStream = events;

  /// The album's identity.
  final String albumKey;

  final ListMusicTracksFn _listTracks;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  List<MusicTrack> _tracks = const [];
  bool _loaded = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  /// The album's tracks the user can read, in album order.
  List<MusicTrack> get tracks => _tracks;

  /// Whether a refresh has succeeded.
  bool get isLoaded => _loaded;

  /// Why the last refresh failed, or null.
  Object? get error => _error;

  /// The album title, from its first track; '' before the first load.
  String get title => _tracks.isEmpty ? '' : _tracks.first.album;

  /// The album artist, from its first track.
  String get albumArtist => _tracks.isEmpty ? '' : _tracks.first.albumArtist;

  /// The earliest tagged year among the tracks, null when none is.
  int? get year {
    final years = [
      for (final t in _tracks)
        if (t.year > 0) t.year,
    ];
    return years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b);
  }

  /// The track whose cover stands for the album: the first with cover art.
  MusicTrack? get coverTrack => _tracks.where((t) => t.hasCover).firstOrNull;

  /// Follows library events and refreshes. Calling it again only refreshes.
  Future<void> start() {
    _events ??= (_eventStream ?? EventsService.instance.events).listen((e) {
      if (e.kind == 'music_library_changed' || e.kind == 'resync') refresh();
    });
    return refresh();
  }

  /// Fetches the album's tracks again.
  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final page = await _listTracks(
        albumKey: albumKey,
        limit: MusicService.maxLimit,
      );
      if (_disposed || generation != _generation) return;
      _tracks = page.items;
      _loaded = true;
      _error = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _error = e;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    super.dispose();
  }
}
