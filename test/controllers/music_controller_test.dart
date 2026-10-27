import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/job.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';

MusicTrack _track(String path) => MusicTrack(relPath: path, title: path);

/// The Music page's state (#3283): the first load, paging, the genre
/// filter, search, rescan and library events.
void main() {
  late List<MusicTrack> library;
  late List<({String? genre, int offset})> trackCalls;
  late Object? failure;
  late StreamController<FileEvent> events;
  late int statusCalls;
  late List<({String sort, int limit})> historyCalls;
  late Object? historyFailure;

  setUp(() {
    library = [for (var i = 0; i < 5; i++) _track('t$i.mp3')];
    trackCalls = [];
    failure = null;
    events = StreamController<FileEvent>.broadcast();
    statusCalls = 0;
    historyCalls = [];
    historyFailure = null;
  });
  tearDown(() => events.close());

  MusicController make({
    Future<List<MusicSearchHit>> Function(String)? search,
    Future<Job> Function()? rescan,
    int pageSize = 2,
  }) {
    final c = MusicController(
      status: () async {
        statusCalls++;
        final f = failure;
        if (f != null) throw f;
        return MusicStatus(trackCount: library.length);
      },
      listTracks:
          ({
            String? albumKey,
            String? artist,
            String? genre,
            String? sort,
            bool descending = false,
            int offset = 0,
            int limit = 200,
          }) async {
            trackCalls.add((genre: genre, offset: offset));
            final matching = genre == null
                ? library
                : library.where((t) => t.genre == genre).toList();
            return MusicListing(
              items: matching.skip(offset).take(pageSize).toList(),
              total: matching.length,
            );
          },
      listAlbums: ({String? artist, int offset = 0, int limit = 200}) async =>
          const MusicListing(
            items: [MusicAlbum(albumKey: 'k', title: 'Blue')],
            total: 1,
          ),
      listArtists: ({int offset = 0, int limit = 200}) async =>
          const MusicListing(items: [MusicArtist(name: 'Joni')], total: 1),
      listGenres: () async => const [MusicGenre(name: 'Folk', trackCount: 5)],
      search: search ?? (q) async => const [],
      rescan:
          rescan ??
          () async => Job(
            id: 7,
            kind: 'music_rescan',
            name: '',
            status: JobStatus.pending,
            createdAt: DateTime.utc(2026),
          ),
      history: ({String sort = 'recent', int limit = 10}) async {
        historyCalls.add((sort: sort, limit: limit));
        final f = historyFailure;
        if (f != null) throw f;
        return [MusicPlay(track: _track('$sort.mp3'), playCount: 1)];
      },
      events: events.stream,
      searchDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Waits for the search in flight to answer.
  Future<void> searched(MusicController c) async {
    while (c.isSearching) {
      final changed = Completer<void>();
      void done() => changed.complete();
      c.addListener(done);
      await changed.future;
      c.removeListener(done);
    }
  }

  test('a refresh loads the status and every listing', () async {
    final c = make();
    expect(c.isLoaded, isFalse);
    await c.refresh();

    expect(c.isLoaded, isTrue);
    expect(c.isEmpty, isFalse);
    expect(c.status!.trackCount, 5);
    expect(c.tracks.map((t) => t.relPath), ['t0.mp3', 't1.mp3']);
    expect(c.hasMoreTracks, isTrue);
    expect(c.albums.single.title, 'Blue');
    expect(c.artists.single.name, 'Joni');
    expect(c.genres.single.name, 'Folk');
    expect(c.error, isNull);
  });

  // #3284.
  test('a refresh loads Recently and Most played', () async {
    final c = make();
    await c.refresh();
    expect(c.recent.single.track.relPath, 'recent.mp3');
    expect(c.mostPlayed.single.track.relPath, 'most.mp3');
    expect(historyCalls, [
      (sort: 'recent', limit: MusicController.historyLength),
      (sort: 'most', limit: MusicController.historyLength),
    ]);
  });

  test('a failed history keeps what it had and fails nothing', () async {
    final c = make();
    await c.refresh();
    historyFailure = ApiException(404, 'music history');
    await c.refresh();

    expect(c.error, isNull);
    expect(c.isLoaded, isTrue);
    expect(c.recent.single.track.relPath, 'recent.mp3');
    expect(c.mostPlayed.single.track.relPath, 'most.mp3');
  });

  test('an empty library is empty, and says whether it is scanning', () async {
    library = [];
    final c = make();
    await c.refresh();
    expect(c.isEmpty, isTrue);
    expect(c.isScanning, isFalse);
  });

  test('a failed refresh keeps the library and reports the cause', () async {
    final c = make();
    await c.refresh();
    failure = ApiException(500, 'status');
    await c.refresh();

    expect(c.tracks, hasLength(2));
    expect(c.error, isA<ApiException>());
    expect(c.errorAction, 'load your music');

    failure = null;
    await c.refresh();
    expect(c.error, isNull);
  });

  test('more songs page in after the ones on screen', () async {
    final c = make();
    await c.refresh();
    await c.loadMoreTracks();
    await c.loadMoreTracks();

    expect(c.tracks.map((t) => t.relPath), [
      for (var i = 0; i < 5; i++) 't$i.mp3',
    ]);
    expect(c.hasMoreTracks, isFalse);
    expect(trackCalls.map((c) => c.offset), [0, 2, 4]);
    // Nothing left: no request.
    await c.loadMoreTracks();
    expect(trackCalls, hasLength(3));
  });

  test('a genre narrows Songs, and null shows every song again', () async {
    library = [
      const MusicTrack(relPath: 'a.mp3', title: 'a', genre: 'Jazz'),
      const MusicTrack(relPath: 'b.mp3', title: 'b'),
    ];
    final c = make();
    await c.refresh();
    await c.setGenre('Jazz');
    expect(c.genre, 'Jazz');
    expect(c.tracks.map((t) => t.relPath), ['a.mp3']);
    expect(c.isEmpty, isFalse);

    await c.setGenre('');
    expect(c.tracks.map((t) => t.relPath), ['b.mp3']);

    await c.setGenre(null);
    expect(c.tracks, hasLength(2));
    expect(trackCalls.last.genre, isNull);
  });

  test('search waits for typing to pause and drops stale answers', () async {
    final asked = <String>[];
    final c = make(
      search: (q) async {
        asked.add(q);
        return [MusicSearchHit(track: _track('$q.mp3'), snippet: q)];
      },
    );
    c.setQuery('ni');
    c.setQuery('nina ');
    expect(c.query, 'nina');
    expect(c.isSearching, isTrue);
    await searched(c);

    expect(asked, ['nina']);
    expect(c.isSearching, isFalse);
    expect(c.results.single.track.relPath, 'nina.mp3');

    c.setQuery('  ');
    expect(c.query, isEmpty);
    expect(c.results, isEmpty);
  });

  test('a failed search keeps its cause apart from the library', () async {
    final c = make(search: (q) async => throw ApiException(501, 'search'));
    await c.refresh();
    c.setQuery('x');
    await searched(c);
    expect(c.searchError, isA<ApiException>());
    expect(c.error, isNull);
  });

  test('a rescan marks the library as scanning', () async {
    library = [];
    final c = make();
    await c.refresh();
    expect(await c.rescan(), isTrue);
    expect(c.isScanning, isTrue);
    expect(c.status!.scanJobId, 7);
  });

  test('a refused rescan says why', () async {
    final c = make(rescan: () async => throw ApiException(403, 'rescan'));
    await c.refresh();
    expect(await c.rescan(), isFalse);
    expect(c.isScanning, isFalse);
    expect(c.errorAction, 'start a music scan');
  });

  test('library and resync events refresh; others do not', () async {
    final c = make();
    await c.start();
    expect(statusCalls, 1);

    events.add(const FileEvent(kind: 'upload', path: 'x.txt'));
    await pumpEventQueue();
    expect(statusCalls, 1);

    events.add(const FileEvent(kind: 'music_library_changed', path: ''));
    await pumpEventQueue();
    expect(statusCalls, 2);

    events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(statusCalls, 3);
  });
}
