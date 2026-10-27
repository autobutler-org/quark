import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/job.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';

/// Fetches one page of tracks; see [MusicService.listTracks].
typedef ListMusicTracksFn =
    Future<MusicListing<MusicTrack>> Function({
      String? albumKey,
      String? artist,
      String? genre,
      String? sort,
      bool descending,
      int offset,
      int limit,
    });

/// Fetches one page of albums; see [MusicService.listAlbums].
typedef ListMusicAlbumsFn =
    Future<MusicListing<MusicAlbum>> Function({
      String? artist,
      int offset,
      int limit,
    });

/// Fetches one page of artists; see [MusicService.listArtists].
typedef ListMusicArtistsFn =
    Future<MusicListing<MusicArtist>> Function({int offset, int limit});

/// Fetches the user's played tracks; see [MusicService.history].
typedef ListMusicHistoryFn =
    Future<List<MusicPlay>> Function({String sort, int limit});

/// State behind the Music page (#3283): the library's status, the four
/// browse listings (Songs, Albums, Artists, Genres), a tag search, and the
/// admin's rescan, and the user's Recently played and Most played (#3284).
///
/// [refresh] fetches the status and the first page of every listing at once,
/// so switching tabs never waits. Songs, Albums and Artists page in with
/// [loadMoreTracks], [loadMoreAlbums] and [loadMoreArtists]. A failed refresh
/// keeps what it had and sets [error]; the next good one clears it. The
/// play history is a nicety beside the library: a history that fails to
/// load keeps what it had and never fails the refresh.
///
/// [start] follows the event stream: `music_library_changed` (the indexer
/// saw a change, or a scan finished) and `resync` refresh. A slow answer
/// cannot overwrite a newer one.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class MusicController extends ChangeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  MusicController({
    Future<MusicStatus> Function() status = MusicService.status,
    ListMusicTracksFn listTracks = MusicService.listTracks,
    ListMusicAlbumsFn listAlbums = MusicService.listAlbums,
    ListMusicArtistsFn listArtists = MusicService.listArtists,
    Future<List<MusicGenre>> Function() listGenres = MusicService.listGenres,
    Future<List<MusicSearchHit>> Function(String query) search =
        MusicService.search,
    Future<Job> Function() rescan = MusicService.rescan,
    ListMusicHistoryFn history = MusicService.history,
    Stream<FileEvent>? events,
    this.searchDebounce = const Duration(milliseconds: 300),
  }) : _status = status,
       _listTracks = listTracks,
       _listAlbums = listAlbums,
       _listArtists = listArtists,
       _listGenres = listGenres,
       _search = search,
       _rescan = rescan,
       _history = history,
       _eventStream = events;

  final Future<MusicStatus> Function() _status;
  final ListMusicTracksFn _listTracks;
  final ListMusicAlbumsFn _listAlbums;
  final ListMusicArtistsFn _listArtists;
  final Future<List<MusicGenre>> Function() _listGenres;
  final Future<List<MusicSearchHit>> Function(String query) _search;
  final Future<Job> Function() _rescan;
  final ListMusicHistoryFn _history;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  /// How long typing pauses before a search is sent.
  final Duration searchDebounce;

  MusicStatus? _libraryStatus;
  MusicListing<MusicTrack> _tracks = const MusicListing.empty();
  MusicListing<MusicAlbum> _albums = const MusicListing.empty();
  MusicListing<MusicArtist> _artists = const MusicListing.empty();
  List<MusicGenre> _genres = const [];
  List<MusicPlay> _recent = const [];
  List<MusicPlay> _mostPlayed = const [];
  String? _genre;
  Object? _error;
  String _errorAction = '';
  bool _isLoadingMore = false;
  bool _isStartingScan = false;
  bool _loaded = false;
  int _generation = 0;

  String _query = '';
  List<MusicSearchHit> _results = const [];
  Object? _searchError;
  bool _isSearching = false;
  int _searchGeneration = 0;
  Timer? _searchTimer;

  bool _disposed = false;

  /// The library's status from the last good refresh, null before one.
  MusicStatus? get status => _libraryStatus;

  /// Whether a refresh has succeeded, so empty listings mean an empty
  /// library rather than nothing fetched yet.
  bool get isLoaded => _loaded;

  /// Whether the library has no tracks the user can read, and no genre
  /// filter is the reason.
  bool get isEmpty => _loaded && _genre == null && _tracks.items.isEmpty;

  /// Whether the Quark is scanning, from [status] or a rescan just queued.
  bool get isScanning => _libraryStatus?.isScanning ?? false;

  /// The Songs listing so far: [genre]'s tracks when it is set.
  List<MusicTrack> get tracks => _tracks.items;

  /// Whether Songs has more tracks to page in.
  bool get hasMoreTracks => _tracks.hasMore;

  /// The Albums listing so far.
  List<MusicAlbum> get albums => _albums.items;

  /// Whether Albums has more to page in.
  bool get hasMoreAlbums => _albums.hasMore;

  /// The Artists listing so far.
  List<MusicArtist> get artists => _artists.items;

  /// Whether Artists has more to page in.
  bool get hasMoreArtists => _artists.hasMore;

  /// Every genre.
  List<MusicGenre> get genres => _genres;

  /// How many songs Recently played and Most played each show.
  static const historyLength = 5;

  /// The songs the user played most recently, newest first.
  List<MusicPlay> get recent => _recent;

  /// The songs the user played most often, most first.
  List<MusicPlay> get mostPlayed => _mostPlayed;

  /// The genre Songs is narrowed to, '' for untagged tracks, null for all.
  String? get genre => _genre;

  /// Why the last refresh or page failed, or null; the page words it with
  /// [errorAction].
  Object? get error => _error;

  /// What failed, as a verb phrase for `Errors.message`.
  String get errorAction => _errorAction;

  /// Whether a further page is being fetched.
  bool get isLoadingMore => _isLoadingMore;

  /// Whether a rescan request is in flight.
  bool get isStartingScan => _isStartingScan;

  /// The search text, trimmed. Empty shows the browse tabs.
  String get query => _query;

  /// The hits for [query], best first.
  List<MusicSearchHit> get results => _results;

  /// Why the last search failed, or null.
  Object? get searchError => _searchError;

  /// Whether a search for [query] is pending or in flight.
  bool get isSearching => _isSearching;

  /// Follows library events and refreshes. Calling it again only refreshes.
  Future<void> start() {
    _events ??= (_eventStream ?? EventsService.instance.events).listen((e) {
      if (e.kind == 'music_library_changed' || e.kind == 'resync') {
        refresh();
      }
    });
    return refresh();
  }

  /// Fetches the status, the first page of every listing, and the play
  /// history.
  Future<void> refresh() async {
    final generation = ++_generation;
    final genre = _genre;
    final history = _loadHistory();
    try {
      final (status, tracks, albums, artists, genres) = await (
        _status(),
        _listTracks(genre: genre, sort: 'title'),
        _listAlbums(),
        _listArtists(),
        _listGenres(),
      ).wait;
      if (!_current(generation)) return;
      _libraryStatus = status;
      _tracks = tracks;
      _albums = albums;
      _artists = artists;
      _genres = genres;
      _loaded = true;
      _error = null;
    } on ParallelWaitError<Object?, Object?> catch (e) {
      if (!_current(generation)) return;
      _fail(_firstError(e), 'load your music');
    }
    final played = await history;
    if (!_current(generation)) return;
    if (played case (final recent, final mostPlayed)) {
      _recent = recent;
      _mostPlayed = mostPlayed;
    }
    _notify();
  }

  /// Recently played and Most played, or null when either failed.
  Future<(List<MusicPlay>, List<MusicPlay>)?> _loadHistory() async {
    try {
      return await (
        _history(sort: 'recent', limit: historyLength),
        _history(sort: 'most', limit: historyLength),
      ).wait;
    } on ParallelWaitError<Object?, Object?> catch (e) {
      debugPrint('[music_controller.dart] history: $e');
      return null;
    }
  }

  /// Narrows Songs to [genre] ('' for untagged), or shows every track for
  /// null, and fetches its first page.
  Future<void> setGenre(String? genre) async {
    if (genre == _genre && _loaded) return;
    _genre = genre;
    final generation = ++_generation;
    try {
      final tracks = await _listTracks(genre: genre, sort: 'title');
      if (!_current(generation)) return;
      _tracks = tracks;
      _error = null;
    } catch (e) {
      if (!_current(generation)) return;
      _fail(e, 'load your music');
    }
    _notify();
  }

  /// Appends the next page of Songs.
  Future<void> loadMoreTracks() => _more(
    _tracks,
    (offset) => _listTracks(genre: _genre, sort: 'title', offset: offset),
    (page) => _tracks = page,
  );

  /// Appends the next page of Albums.
  Future<void> loadMoreAlbums() => _more(
    _albums,
    (offset) => _listAlbums(offset: offset),
    (page) => _albums = page,
  );

  /// Appends the next page of Artists.
  Future<void> loadMoreArtists() => _more(
    _artists,
    (offset) => _listArtists(offset: offset),
    (page) => _artists = page,
  );

  /// Searches the tags for [text] once typing pauses for [searchDebounce].
  /// Blank text clears the search.
  void setQuery(String text) {
    final query = text.trim();
    if (query == _query) return;
    _query = query;
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    _searchError = null;
    if (query.isEmpty) {
      _results = const [];
      _isSearching = false;
      _notify();
      return;
    }
    _isSearching = true;
    _notify();
    _searchTimer = Timer(searchDebounce, () => _runSearch(query, generation));
  }

  /// Queues a full rescan, admin only. Returns whether the Quark took it.
  Future<bool> rescan() async {
    if (_isStartingScan) return false;
    _isStartingScan = true;
    _notify();
    var queued = false;
    try {
      final job = await _rescan();
      queued = true;
      _libraryStatus = MusicStatus(
        trackCount: _libraryStatus?.trackCount ?? 0,
        lastScanAt: _libraryStatus?.lastScanAt,
        scanJobId: job.id,
      );
      _error = null;
    } catch (e) {
      _fail(e, 'start a music scan');
    }
    _isStartingScan = false;
    _notify();
    return queued;
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final results = await _search(query);
      if (_disposed || generation != _searchGeneration) return;
      _results = results;
      _searchError = null;
    } catch (e) {
      if (_disposed || generation != _searchGeneration) return;
      _results = const [];
      _searchError = e;
    }
    _isSearching = false;
    _notify();
  }

  Future<void> _more<T>(
    MusicListing<T> current,
    Future<MusicListing<T>> Function(int offset) fetch,
    void Function(MusicListing<T>) store,
  ) async {
    if (_isLoadingMore || !current.hasMore) return;
    _isLoadingMore = true;
    _notify();
    final generation = _generation;
    try {
      final next = await fetch(current.items.length);
      // A refresh or genre change since replaced the listing this extends.
      if (_current(generation)) store(current.followedBy(next));
    } catch (e) {
      if (_current(generation)) _fail(e, 'load more of your music');
    }
    _isLoadingMore = false;
    _notify();
  }

  void _fail(Object error, String action) {
    _error = error;
    _errorAction = action;
  }

  static Object _firstError(ParallelWaitError<Object?, Object?> e) =>
      switch (e.errors) {
        (
          AsyncError? a,
          AsyncError? b,
          AsyncError? c,
          AsyncError? d,
          AsyncError? f,
        ) =>
          (a ?? b ?? c ?? d ?? f)?.error ?? e,
        _ => e,
      };

  bool _current(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _events?.cancel();
    super.dispose();
  }
}
