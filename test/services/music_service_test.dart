import 'package:flutter_test/flutter_test.dart';
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

  test('a refusal throws the status for Errors to read', () async {
    answer(500, {'error': 'boom'});
    await expectLater(
      MusicService.listAlbums(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
    );
  });
}
