import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';

/// The Music page's state (#3283): loading the library, filtering songs by
/// genre, fetching again on `music_library_changed`, and search's 501 on a
/// Quark running PostgreSQL.
void main() {
  late List<MusicTrack> library;
  late List<({String? albumKey, String? artist, String? genre})> trackCalls;
  late Object? failure;
  late Object? searchFailure;
  late StreamController<FileEvent> events;

  setUp(() {
    library = const [
      MusicTrack(relPath: 'a.mp3', title: 'So What', genre: 'Jazz'),
      MusicTrack(relPath: 'b.mp3', title: 'Paranoid', genre: 'Metal'),
    ];
    trackCalls = [];
    failure = null;
    searchFailure = null;
    events = StreamController<FileEvent>.broadcast();
  });
  tearDown(() => events.close());

  MusicController build({String? albumKey, String? artist}) {
    final controller = MusicController(
      albumKey: albumKey,
      artist: artist,
      listTracks: ({albumKey, artist, genre}) async {
        trackCalls.add((albumKey: albumKey, artist: artist, genre: genre));
        final f = failure;
        if (f != null) throw f;
        return [
          for (final t in library)
            if (genre == null || t.genre == genre) t,
        ];
      },
      listAlbums: ({artist}) async => const [MusicAlbum(key: 'k', title: 'X')],
      listArtists: () async => const [MusicArtist(name: 'Miles Davis')],
      listGenres: () async => const [MusicGenre(name: 'Jazz', trackCount: 1)],
      status: () async => const MusicStatus(trackCount: 2),
      search: (query) async {
        final f = searchFailure;
        if (f != null) throw f;
        final MusicSearchHit hit = (track: library.first, snippet: query);
        return [hit];
      },
      events: events.stream,
      searchDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('loads the whole library', () async {
    final controller = build();
    await controller.refresh();

    expect(controller.tracks, hasLength(2));
    expect(controller.albums.single.key, 'k');
    expect(controller.artists.single.name, 'Miles Davis');
    expect(controller.genres.single.name, 'Jazz');
    expect(controller.status?.trackCount, 2);
    expect(controller.error, isNull);
  });

  test(
    'drops blank-named albums, artists and genres but keeps the songs',
    () async {
      const untagged = MusicTrack(relPath: 'untagged.mp3', title: 'untagged');
      final controller = MusicController(
        listTracks: ({albumKey, artist, genre}) async => const [untagged],
        listAlbums: ({artist}) async => const [
          MusicAlbum(key: 'blank', title: ''),
          MusicAlbum(key: 'space', title: '  '),
          MusicAlbum(key: 'k', title: 'X'),
        ],
        listArtists: () async => const [
          MusicArtist(name: ''),
          MusicArtist(name: ' '),
          MusicArtist(name: 'Miles Davis'),
        ],
        listGenres: () async => const [
          MusicGenre(name: '', trackCount: 1),
          MusicGenre(name: '\t', trackCount: 1),
          MusicGenre(name: 'Jazz', trackCount: 1),
        ],
        status: () async => const MusicStatus(trackCount: 1),
        events: events.stream,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      expect(controller.albums.single.key, 'k');
      expect(controller.artists.single.name, 'Miles Davis');
      expect(controller.genres.single.name, 'Jazz');
      expect(controller.tracks.single.title, 'untagged');
    },
  );

  test("an album lists only its tracks", () async {
    final controller = build(albumKey: 'kob');
    await controller.refresh();

    expect(trackCalls.single.albumKey, 'kob');
    expect(controller.albums, isEmpty);
    expect(controller.artists, isEmpty);
    expect(controller.status, isNull);
  });

  test('an artist lists their albums and tracks', () async {
    final controller = build(artist: 'Miles Davis');
    await controller.refresh();

    expect(trackCalls.single.artist, 'Miles Davis');
    expect(controller.albums.single.key, 'k');
    expect(controller.genres, isEmpty);
  });

  test('filters the songs by genre and clears the filter', () async {
    final controller = build();
    await controller.refresh();

    await controller.filterGenre('Jazz');
    expect(controller.genre, 'Jazz');
    expect([for (final t in controller.tracks) t.title], ['So What']);

    await controller.filterGenre(null);
    expect(controller.tracks, hasLength(2));
  });

  test('a failed refresh keeps what it had', () async {
    final controller = build();
    await controller.refresh();
    failure = ApiException(500, 'list');
    await controller.refresh();

    expect(controller.tracks, hasLength(2));
    expect(controller.error, isA<ApiException>());
  });

  test('music_library_changed fetches again', () async {
    final controller = build();
    await controller.refresh();
    library = const [MusicTrack(relPath: 'c.mp3', title: 'Blue in Green')];

    events.add(const FileEvent(kind: 'upload', path: 'c.mp3'));
    await pumpEventQueue();
    expect(trackCalls, hasLength(1));

    events.add(const FileEvent(kind: 'music_library_changed', path: ''));
    await pumpEventQueue();
    expect(trackCalls, hasLength(2));
    expect(controller.tracks.single.title, 'Blue in Green');
  });

  test('searches, and an empty query ends the search', () async {
    final controller = build();
    controller.search(' so ');
    expect(controller.isSearching, isTrue);
    await pumpEventQueue();

    expect(controller.query, 'so');
    expect(controller.isSearching, isFalse);
    expect(controller.results.single.track.title, 'So What');

    controller.search('');
    expect(controller.results, isEmpty);
    expect(controller.isSearching, isFalse);
  });

  test("search's 501 on PostgreSQL reads as unsupported", () async {
    searchFailure = ApiException(501, 'search music');
    final controller = build();
    controller.search('so');
    await pumpEventQueue();

    expect(controller.results, isEmpty);
    expect(
      Errors.message(controller.searchError, 'search your music'),
      "Your Quark doesn't support that yet.",
    );
  });

  test('a rescan lists the library again', () async {
    var scansQueued = 0;
    final controller = MusicController(
      listTracks: ({albumKey, artist, genre}) async => const [],
      listAlbums: ({artist}) async => const [],
      listArtists: () async => const [],
      listGenres: () async => const [],
      status: () async => MusicStatus(scanJobId: scansQueued > 0 ? 4 : null),
      rescan: () async => scansQueued++,
      events: events.stream,
    );
    addTearDown(controller.dispose);

    expect(await controller.rescan(), isNull);
    expect(scansQueued, 1);
    expect(controller.status?.isScanning, isTrue);
  });
}
