import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/music_album_controller.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/utils/error_text.dart';

/// One album's page state (#3283): its tracks, and the title, artist, year
/// and cover read from them.
void main() {
  test('reads the album from its tracks', () async {
    String? askedKey;
    Object? failure;
    final c = MusicAlbumController(
      albumKey: 'k1',
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
            askedKey = albumKey;
            final f = failure;
            if (f != null) throw f;
            return const MusicListing(
              items: [
                MusicTrack(
                  relPath: '1.flac',
                  title: 'One',
                  album: 'Blue',
                  albumArtist: 'Joni Mitchell',
                  year: 1972,
                ),
                MusicTrack(
                  relPath: '2.flac',
                  title: 'Two',
                  album: 'Blue',
                  year: 1971,
                  hasCover: true,
                ),
              ],
              total: 2,
            );
          },
      events: const Stream.empty(),
    );
    addTearDown(c.dispose);

    await c.start();
    expect(askedKey, 'k1');
    expect(c.isLoaded, isTrue);
    expect(c.title, 'Blue');
    expect(c.albumArtist, 'Joni Mitchell');
    expect(c.year, 1971);
    expect(c.coverTrack!.relPath, '2.flac');

    failure = ApiException(500, 'tracks');
    await c.refresh();
    expect(c.tracks, hasLength(2));
    expect(c.error, isA<ApiException>());
  });

  test('an album with no tagged year or cover has neither', () async {
    final c = MusicAlbumController(
      albumKey: 'k',
      listTracks:
          ({
            String? albumKey,
            String? artist,
            String? genre,
            String? sort,
            bool descending = false,
            int offset = 0,
            int limit = 200,
          }) async => const MusicListing(
            items: [MusicTrack(relPath: 'a.mp3', title: 'a')],
            total: 1,
          ),
      events: const Stream.empty(),
    );
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.year, isNull);
    expect(c.coverTrack, isNull);
  });
}
