import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Lists tracks, keeping those of [albumKey], album [artist] or [genre].
typedef ListMusicTracksFn =
    Future<List<MusicTrack>> Function({
      String? albumKey,
      String? artist,
      String? genre,
    });

/// Lists albums, keeping album [artist]'s.
typedef ListMusicAlbumsFn = Future<List<MusicAlbum>> Function({String? artist});

/// State behind the Music pages (#3283): the library's songs, albums,
/// artists and genres, its scan status, a genre filter on the songs, and
/// search.
///
/// One controller serves all three pages. With neither [albumKey] nor
/// [artist] it is the whole library; with [albumKey] it lists that album's
/// tracks; with [artist] that album artist's albums and tracks. It fetches
/// again on `music_library_changed` and `resync`.
///
/// A failed refresh keeps what it had and sets [error]; a failed search sets
/// [searchError], which is how a Quark on PostgreSQL's 501 reaches the page.
/// Both are the thrown objects, for the page to word with `Errors.message`.
/// Service calls arrive as parameters defaulting to [MusicService], so a
/// test passes fakes.
class MusicController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream;
  /// [searchDelay] is how long typing pauses before a search goes out.
  MusicController({
    this.albumKey,
    this.artist,
    ListMusicTracksFn listTracks = MusicService.listTracks,
    ListMusicAlbumsFn listAlbums = MusicService.listAlbums,
    Future<List<MusicArtist>> Function() listArtists = MusicService.listArtists,
    Future<List<MusicGenre>> Function() listGenres = MusicService.listGenres,
    Future<List<MusicSearchHit>> Function(String query) search =
        MusicService.search,
    Future<MusicStatus> Function() status = MusicService.status,
    Future<void> Function() rescan = MusicService.rescan,
    Stream<FileEvent>? events,
    this.searchDelay = const Duration(milliseconds: 300),
  }) : _listTracks = listTracks,
       _listAlbums = listAlbums,
       _listArtists = listArtists,
       _listGenres = listGenres,
       _search = search,
       _status = status,
       _rescan = rescan {
    _events = (events ?? EventsService.instance.events).listen((event) {
      if (event.kind == 'music_library_changed' || event.kind == 'resync') {
        refresh();
      }
    });
  }

  /// The album this controller lists, or null.
  final String? albumKey;

  /// The album artist this controller lists, or null.
  final String? artist;

  /// How long [search] waits for typing to pause.
  final Duration searchDelay;

  final ListMusicTracksFn _listTracks;
  final ListMusicAlbumsFn _listAlbums;
  final Future<List<MusicArtist>> Function() _listArtists;
  final Future<List<MusicGenre>> Function() _listGenres;
  final Future<List<MusicSearchHit>> Function(String query) _search;
  final Future<MusicStatus> Function() _status;
  final Future<void> Function() _rescan;
  late final StreamSubscription<FileEvent> _events;
  Timer? _searchTimer;

  List<MusicTrack> _tracks = const [];
  List<MusicAlbum> _albums = const [];
  List<MusicArtist> _artists = const [];
  List<MusicGenre> _genres = const [];
  MusicStatus? _statusValue;
  Object? _error;
  String? _genre;
  String _query = '';
  List<MusicSearchHit> _results = const [];
  bool _searching = false;
  Object? _searchError;

  /// The tracks from the last good listing, in album order.
  List<MusicTrack> get tracks => _tracks;

  /// The albums from the last good listing, without blank-titled ones.
  /// Empty for an album.
  List<MusicAlbum> get albums => _albums;

  /// The album artists, without blank-named ones. Listed only for the whole
  /// library.
  List<MusicArtist> get artists => _artists;

  /// The genres, without blank-named ones. Listed only for the whole
  /// library.
  List<MusicGenre> get genres => _genres;

  /// The library's status, null before the first good listing and for an
  /// album or artist.
  MusicStatus? get status => _statusValue;

  /// The thrown object from the last failed refresh, null after a good one.
  Object? get error => _error;

  /// The genre [tracks] is filtered to, or null for every genre.
  String? get genre => _genre;

  /// The search text; empty when not searching.
  String get query => _query;

  /// The hits for [query], best first.
  List<MusicSearchHit> get results => _results;

  /// Whether a search for [query] is on its way.
  bool get isSearching => _searching;

  /// The thrown object from the last failed search, null after a good one.
  Object? get searchError => _searchError;

  bool get _isLibrary => albumKey == null && artist == null;

  /// Fetches everything this controller lists again.
  Future<void> refresh() async {
    try {
      final results = await Future.wait<Object?>([
        _listTracks(albumKey: albumKey, artist: artist, genre: _genre),
        albumKey == null ? _listAlbums(artist: artist) : Future.value(null),
        _isLibrary ? _listArtists() : Future.value(null),
        _isLibrary ? _listGenres() : Future.value(null),
        _isLibrary ? _status() : Future.value(null),
      ]);
      _tracks = results[0]! as List<MusicTrack>;
      // Untagged files group under a blank album, artist and genre; a
      // blank row has nothing to show or link to, so it is dropped here.
      // Their tracks still list under Songs.
      _albums = [
        for (final a in results[1] as List<MusicAlbum>? ?? const <MusicAlbum>[])
          if (a.title.trim().isNotEmpty) a,
      ];
      _artists = [
        for (final a
            in results[2] as List<MusicArtist>? ?? const <MusicArtist>[])
          if (a.name.trim().isNotEmpty) a,
      ];
      _genres = [
        for (final g in results[3] as List<MusicGenre>? ?? const <MusicGenre>[])
          if (g.name.trim().isNotEmpty) g,
      ];
      _statusValue = results[4] as MusicStatus?;
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  /// Filters [tracks] to [genre], or clears the filter for null, and lists
  /// them again.
  Future<void> filterGenre(String? genre) async {
    _genre = genre;
    notifyListeners();
    try {
      final tracks = await _listTracks(
        albumKey: albumKey,
        artist: artist,
        genre: genre,
      );
      if (_genre != genre) return;
      _tracks = tracks;
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  /// Searches for [query] once typing pauses for [searchDelay]. Empty text
  /// ends the search.
  void search(String query) {
    _searchTimer?.cancel();
    _query = query.trim();
    _searchError = null;
    if (_query.isEmpty) {
      _results = const [];
      _searching = false;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _searchTimer = Timer(searchDelay, () => _runSearch(_query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await _search(query);
      if (query != _query) return;
      _results = results;
    } catch (e) {
      if (query != _query) return;
      _results = const [];
      _searchError = e;
    }
    _searching = false;
    notifyListeners();
  }

  /// Queues a scan of the library, then lists it again so the page shows
  /// the scan under way. Returns the thrown object when the Quark refused,
  /// or null.
  Future<Object?> rescan() async {
    try {
      await _rescan();
    } catch (e) {
      return e;
    }
    await refresh();
    return null;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _events.cancel();
    super.dispose();
  }
}
