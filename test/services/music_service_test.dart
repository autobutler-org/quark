import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// The music library API a slideshow picks its music from (#4179).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  test('lists the albums', () async {
    answer(200, {
      'albums': [
        {
          'albumKey': 'k1',
          'title': 'Blue',
          'albumArtist': 'Joni Mitchell',
          'trackCount': 10,
        },
      ],
      'total': 1,
    });

    final album = (await MusicService.listAlbums()).single;

    expect(requests.single.url.path, '/api/v0/music/albums');
    expect(requests.single.url.queryParameters['limit'], '200');
    expect(album.key, 'k1');
    expect(album.title, 'Blue');
    expect(album.albumArtist, 'Joni Mitchell');
    expect(album.trackCount, 10);
  });

  test("lists an album's tracks", () async {
    answer(200, {
      'tracks': [
        {
          'relPath': 'Music/Blue/01 All I Want.mp3',
          'serial': 'STICK',
          'title': 'All I Want',
        },
      ],
      'total': 1,
    });

    final track = (await MusicService.listAlbumTracks('k 1')).single;

    expect(requests.single.url.path, '/api/v0/music/tracks');
    expect(requests.single.url.queryParameters['albumKey'], 'k 1');
    expect(track.relPath, 'Music/Blue/01 All I Want.mp3');
    expect(track.serial, 'STICK');
    expect(track.title, 'All I Want');
  });

  test('reads every tag of a track, and filters by genre', () async {
    answer(200, {
      'tracks': [
        {
          'serial': '',
          'relPath': 'Music/Kind of Blue/01 So What.flac',
          'title': 'So What',
          'artist': 'Miles Davis',
          'albumArtist': 'Miles Davis',
          'album': 'Kind of Blue',
          'albumKey': 'kob',
          'genre': 'Jazz',
          'trackNo': 1,
          'discNo': 1,
          'year': 1959,
          'durationMs': 562000,
          'durationExact': true,
          'hasCover': true,
        },
      ],
      'total': 1,
    });

    final track = (await MusicService.listTracks(genre: 'Jazz')).single;

    final query = requests.single.url.queryParameters;
    expect(query['genre'], 'Jazz');
    expect(query.containsKey('albumKey'), isFalse);
    expect(track.artist, 'Miles Davis');
    expect(track.album, 'Kind of Blue');
    expect(track.albumKey, 'kob');
    expect(track.genre, 'Jazz');
    expect(track.durationMs, 562000);
    expect(track.hasCover, isTrue);
  });

  test('pages through a listing until its total', () async {
    answerWith((request) {
      final offset = int.parse(request.url.queryParameters['offset']!);
      return http.Response(
        jsonEncode({
          'artists': [
            if (offset < 2) {'name': 'A$offset'},
          ],
          'total': 2,
        }),
        200,
      );
    });

    final artists = await MusicService.listArtists();

    expect([for (final a in artists) a.name], ['A0', 'A1']);
    expect(requests, hasLength(2));
  });

  test('reads artists, genres and an album cover', () async {
    answerWith(
      (request) => http.Response(
        jsonEncode(switch (request.url.path) {
          '/api/v0/music/artists' => {
            'artists': [
              {
                'name': 'Nina Simone',
                'albumCount': 2,
                'trackCount': 20,
                'coverPath': 'Music/Nina/01.mp3',
                'coverSerial': 'STICK',
              },
            ],
            'total': 1,
          },
          '/api/v0/music/genres' => {
            'genres': [
              {'name': 'Soul', 'trackCount': 20},
            ],
          },
          _ => {
            'albums': [
              {
                'albumKey': 'k',
                'title': 'Pastel Blues',
                'year': 1965,
                'coverPath': 'Music/Nina/01.mp3',
                'coverSerial': 'STICK',
              },
            ],
            'total': 1,
          },
        }),
        200,
      ),
    );

    final artist = (await MusicService.listArtists()).single;
    final genre = (await MusicService.listGenres()).single;
    final album = (await MusicService.listAlbums(artist: 'Nina Simone')).single;

    expect(artist.albumCount, 2);
    expect(artist.trackCount, 20);
    expect(artist.coverSerial, 'STICK');
    expect(genre.name, 'Soul');
    expect(genre.trackCount, 20);
    expect(requests.last.url.queryParameters['artist'], 'Nina Simone');
    expect(album.year, 1965);
    expect(album.coverPath, 'Music/Nina/01.mp3');
  });

  test('searches and reads each hit', () async {
    answer(200, {
      'results': [
        {
          'track': {'relPath': 'a.mp3', 'title': 'Feeling Good'},
          'snippet': '<b>Feeling</b> Good',
        },
      ],
    });

    final hit = (await MusicService.search('feeling')).single;

    expect(requests.single.url.path, '/api/v0/music/search');
    expect(requests.single.url.queryParameters['q'], 'feeling');
    expect(hit.track.title, 'Feeling Good');
    expect(hit.snippet, '<b>Feeling</b> Good');
  });

  test('a Quark on PostgreSQL refuses search with 501', () async {
    answer(501, {'error': 'not implemented'});
    await expectLater(
      MusicService.search('x'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 501)),
    );
  });

  test('reads the status, scanning or not', () async {
    answer(200, {
      'trackCount': 0,
      'lastScanAt': '2026-01-02T03:04:05Z',
      'scanJobId': 7,
    });
    final scanning = await MusicService.status();
    expect(scanning.trackCount, 0);
    expect(scanning.scanJobId, 7);
    expect(scanning.isScanning, isTrue);
    expect(scanning.lastScanAt, DateTime.utc(2026, 1, 2, 3, 4, 5));

    answer(200, {'trackCount': 3, 'lastScanAt': null});
    final idle = await MusicService.status();
    expect(idle.isScanning, isFalse);
    expect(idle.lastScanAt, isNull);
  });

  test('queues a rescan', () async {
    answer(202, {'id': 9, 'kind': 'music_rescan'});
    await MusicService.rescan();
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/music/rescan');

    answer(403, {'error': 'admin only'});
    await expectLater(
      MusicService.rescan(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });

  test('a refusal throws the status for Errors to read', () async {
    answer(500, {'error': 'boom'});
    await expectLater(
      MusicService.listAlbums(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
    );
  });
}
