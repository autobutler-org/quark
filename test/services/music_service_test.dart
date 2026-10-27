import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';

/// The music API (#3280) read into the app's models (#3283).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  void answer(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('lists tracks with the filters it was given', () async {
    answer(200, {
      'tracks': [
        {
          'serial': 'USB1',
          'relPath': 'music/Kind of Blue/01 So What.flac',
          'title': 'So What',
          'artist': 'Miles Davis',
          'albumArtist': 'Miles Davis',
          'album': 'Kind of Blue',
          'albumKey': 'abc',
          'genre': 'Jazz',
          'trackNo': 1,
          'discNo': 1,
          'year': 1959,
          'durationMs': 562000,
          'durationExact': true,
          'hasCover': true,
        },
      ],
      'total': 5,
    });

    final page = await MusicService.listTracks(genre: '', sort: 'title');

    final url = requests.single.url;
    expect(url.path, '/api/v0/music/tracks');
    expect(url.queryParameters['genre'], '');
    expect(url.queryParameters['sort'], 'title');
    expect(url.queryParameters.containsKey('artist'), isFalse);
    expect(url.queryParameters.containsKey('albumKey'), isFalse);
    expect(page.total, 5);
    final track = page.items.single;
    expect(track.serial, 'USB1');
    expect(track.title, 'So What');
    expect(track.albumKey, 'abc');
    expect(track.duration, const Duration(milliseconds: 562000));
    expect(track.hasCover, isTrue);
  });

  test('lists one artist\'s albums', () async {
    answer(200, {
      'albums': [
        {
          'albumKey': 'abc',
          'title': 'Kind of Blue',
          'albumArtist': 'Miles Davis',
          'year': 1959,
          'trackCount': 5,
          'durationMs': 1000,
          'coverSerial': '',
          'coverPath': 'music/kob/01.flac',
        },
      ],
      'total': 1,
    });

    final album = (await MusicService.listAlbums(
      artist: 'Miles Davis',
    )).items.single;

    expect(requests.single.url.path, '/api/v0/music/albums');
    expect(requests.single.url.queryParameters['artist'], 'Miles Davis');
    expect(album.title, 'Kind of Blue');
    expect(album.trackCount, 5);
    expect(album.coverPath, 'music/kob/01.flac');
  });

  test('reads artists, genres, search hits and status', () async {
    answer(200, {
      'artists': [
        {'name': 'Nina Simone', 'albumCount': 2, 'trackCount': 20},
      ],
      'genres': [
        {'name': 'Jazz', 'trackCount': 7},
      ],
      'results': [
        {
          'track': {'relPath': 'a.mp3', 'title': 'Feeling Good'},
          'snippet': 'Feeling [Good]',
        },
      ],
      'trackCount': 42,
      'lastScanAt': '2026-10-01T12:00:00Z',
      'scanJobId': 9,
    });

    expect((await MusicService.listArtists()).items.single.albumCount, 2);
    expect((await MusicService.listGenres()).single.trackCount, 7);
    final hit = (await MusicService.search('good')).single;
    expect(requests.last.url.queryParameters['q'], 'good');
    expect(hit.track.title, 'Feeling Good');
    expect(hit.snippet, 'Feeling [Good]');
    final status = await MusicService.status();
    expect(status.trackCount, 42);
    expect(status.isScanning, isTrue);
    expect(status.lastScanAt, DateTime.utc(2026, 10, 1, 12));
  });

  test('a status with no scan running is not scanning', () async {
    answer(200, {'trackCount': 0, 'lastScanAt': null});
    final status = await MusicService.status();
    expect(status.isScanning, isFalse);
    expect(status.lastScanAt, isNull);
  });

  test('rescan posts and reads the queued job', () async {
    answer(202, {'id': 3, 'kind': 'music_rescan', 'status': 'queued'});
    final job = await MusicService.rescan();
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/music/rescan');
    expect(job.id, 3);
    expect(job.kind, 'music_rescan');
  });

  test('a refusal throws the status for Errors to read', () async {
    answer(501, {'error': 'Music search needs SQLite'});
    await expectLater(
      MusicService.search('x'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 501)),
    );
  });
}
