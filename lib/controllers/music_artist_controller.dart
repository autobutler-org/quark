import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';

/// State behind one album artist's page (#3283): their albums, and their
/// songs by album, paged in with [loadMoreTracks].
///
/// [name] is matched without case; '' is the untagged artist. A failed
/// refresh keeps what it had and sets [error], and `music_library_changed`
/// or `resync` refresh after [start].
class MusicArtistController extends ChangeNotifier {
  /// Creates the controller for [name]. The service calls default to the
  /// real ones and [events] to the app's event stream.
  MusicArtistController({
    required this.name,
    ListMusicAlbumsFn listAlbums = MusicService.listAlbums,
    ListMusicTracksFn listTracks = MusicService.listTracks,
    Stream<FileEvent>? events,
  }) : _listAlbums = listAlbums,
       _listTracks = listTracks,
       _eventStream = events;

  /// The album artist's name.
  final String name;

  final ListMusicAlbumsFn _listAlbums;
  final ListMusicTracksFn _listTracks;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  List<MusicAlbum> _albums = const [];
  MusicListing<MusicTrack> _tracks = const MusicListing.empty();
  bool _loaded = false;
  bool _isLoadingMore = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  /// The artist's albums, by title.
  List<MusicAlbum> get albums => _albums;

  /// The artist's songs fetched so far, by album.
  List<MusicTrack> get tracks => _tracks.items;

  /// Whether more songs are left to page in.
  bool get hasMoreTracks => _tracks.hasMore;

  /// Whether a further page of songs is being fetched.
  bool get isLoadingMore => _isLoadingMore;

  /// Whether a refresh has succeeded.
  bool get isLoaded => _loaded;

  /// Why the last refresh or page failed, or null.
  Object? get error => _error;

  /// Follows library events and refreshes. Calling it again only refreshes.
  Future<void> start() {
    _events ??= (_eventStream ?? EventsService.instance.events).listen((e) {
      if (e.kind == 'music_library_changed' || e.kind == 'resync') refresh();
    });
    return refresh();
  }

  /// Fetches the albums and the first page of songs again.
  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final (albums, tracks) = await (
        _listAlbums(artist: name, limit: MusicService.maxLimit),
        _listTracks(artist: name, sort: 'album'),
      ).wait;
      if (!_current(generation)) return;
      _albums = albums.items;
      _tracks = tracks;
      _loaded = true;
      _error = null;
    } on ParallelWaitError<Object?, Object?> catch (e) {
      if (!_current(generation)) return;
      _error = switch (e.errors) {
        (AsyncError? a, AsyncError? b) => (a ?? b)?.error ?? e,
        _ => e,
      };
    }
    _notify();
  }

  /// Appends the next page of songs.
  Future<void> loadMoreTracks() async {
    if (_isLoadingMore || !_tracks.hasMore) return;
    _isLoadingMore = true;
    _notify();
    final generation = _generation;
    try {
      final next = await _listTracks(
        artist: name,
        sort: 'album',
        offset: _tracks.items.length,
      );
      if (_current(generation)) _tracks = _tracks.followedBy(next);
    } catch (e) {
      if (_current(generation)) _error = e;
    }
    _isLoadingMore = false;
    _notify();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    super.dispose();
  }
}
