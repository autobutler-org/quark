import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/music_artist_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/utils/error_text.dart';

/// One album artist's page state (#3283): their albums and their songs,
/// paged in.
void main() {
  test('loads the artist\'s albums and pages in their songs', () async {
    final artists = <String?>[];
    final songs = [
      for (var i = 0; i < 3; i++) MusicTrack(relPath: '$i.mp3', title: '$i'),
    ];
    Object? albumFailure;
    final c = MusicArtistController(
      name: '',
      listAlbums: ({String? artist, int offset = 0, int limit = 200}) async {
        artists.add(artist);
        final f = albumFailure;
        if (f != null) throw f;
        return const MusicListing(
          items: [MusicAlbum(albumKey: 'k', title: 'Untitled')],
          total: 1,
        );
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
            artists.add(artist);
            expect(sort, 'album');
            return MusicListing(
              items: songs.skip(offset).take(2).toList(),
              total: songs.length,
            );
          },
      events: const Stream.empty(),
    );
    addTearDown(c.dispose);

    await c.start();
    // The untagged artist is asked for by its empty name, not left out.
    expect(artists, ['', '']);
    expect(c.albums.single.title, 'Untitled');
    expect(c.tracks, hasLength(2));
    expect(c.hasMoreTracks, isTrue);

    await c.loadMoreTracks();
    expect(c.tracks.map((t) => t.relPath), ['0.mp3', '1.mp3', '2.mp3']);
    expect(c.hasMoreTracks, isFalse);

    albumFailure = ApiException(500, 'albums');
    await c.refresh();
    expect(c.error, isA<ApiException>());
    expect(c.albums, hasLength(1));
  });
}
