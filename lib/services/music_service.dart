import 'dart:convert';

import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// One search hit: the track, and the tag that matched with the matched
/// terms in `<b>…</b>`.
typedef MusicSearchHit = ({MusicTrack track, String snippet});

/// The music library API under `/api/v0/music`: the songs, albums, artists
/// and genres the signed-in user can read, search over them, the library's
/// scan status, and queuing a rescan.
class MusicService with AuthenticatedService {
  MusicService._();
  static final MusicService instance = MusicService._();

  /// The most the Quark answers in one page.
  static const int _pageSize = 200;

  /// Lists the music albums, ordered by album artist and title, every page
  /// of them. [artist] keeps one album artist's albums.
  ///
  /// api: GET /api/v0/music/albums
  static Future<List<MusicAlbum>> listAlbums({String? artist}) async => [
    for (final album in await _pages('/api/v0/music/albums', 'albums', {
      'artist': ?artist,
    }, 'list music albums'))
      MusicAlbum.fromJson(album),
  ];

  /// Lists the tracks, every page of them, in album order: album, disc,
  /// then track. [albumKey], [artist] (the album artist) and [genre] keep
  /// only the matching ones.
  ///
  /// api: GET /api/v0/music/tracks
  static Future<List<MusicTrack>> listTracks({
    String? albumKey,
    String? artist,
    String? genre,
  }) async => [
    for (final track in await _pages('/api/v0/music/tracks', 'tracks', {
      'albumKey': ?albumKey,
      'artist': ?artist,
      'genre': ?genre,
    }, 'list music tracks'))
      MusicTrack.fromJson(track),
  ];

  /// Lists the tracks of the album [albumKey] in album order: disc, then
  /// track.
  ///
  /// api: none
  static Future<List<MusicTrack>> listAlbumTracks(String albumKey) =>
      listTracks(albumKey: albumKey);

  /// Lists the album artists, every page of them, by name.
  ///
  /// api: GET /api/v0/music/artists
  static Future<List<MusicArtist>> listArtists() async => [
    for (final artist in await _pages(
      '/api/v0/music/artists',
      'artists',
      const {},
      'list music artists',
    ))
      MusicArtist.fromJson(artist),
  ];

  /// Lists the genres by name.
  ///
  /// api: GET /api/v0/music/genres
  static Future<List<MusicGenre>> listGenres() async {
    final json = await _get('/api/v0/music/genres', const {}, 'list genres');
    return [
      for (final genre in _list(json['genres'])) MusicGenre.fromJson(genre),
    ];
  }

  /// Searches the library's tags for [query], best match first. A Quark on
  /// PostgreSQL answers 501, thrown as an [ApiException] for `Errors` to
  /// read.
  ///
  /// api: GET /api/v0/music/search
  static Future<List<MusicSearchHit>> search(String query) async {
    final json = await _get('/api/v0/music/search', {
      'q': query,
      'limit': '$_pageSize',
    }, 'search music');
    return [
      for (final hit in _list(json['results']))
        (
          track: MusicTrack.fromJson(
            hit['track'] is Map<String, dynamic>
                ? hit['track'] as Map<String, dynamic>
                : const {},
          ),
          snippet: hit['snippet']?.toString() ?? '',
        ),
    ];
  }

  /// The library's track count and whether a scan is under way.
  ///
  /// api: GET /api/v0/music/status
  static Future<MusicStatus> status() async => MusicStatus.fromJson(
    await _get('/api/v0/music/status', const {}, 'read music status'),
  );

  /// Queues a scan of every drive's music, for an admin. Its progress shows
  /// through the usual `job_*` events.
  ///
  /// api: POST /api/v0/music/rescan
  static Future<void> rescan() async {
    final response = await instance.authenticatedPost(
      apiBaseUri.replace(path: '/api/v0/music/rescan'),
    );
    if (response.statusCode != 202 && response.statusCode != 200) {
      throw ApiException(response.statusCode, 'rescan music');
    }
  }

  /// GETs every page of the listing at [path], reading each page's [key]
  /// until `total` is reached.
  ///
  /// ponytail: holds the whole listing in memory; page lazily as the list
  /// scrolls if libraries outgrow that.
  ///
  /// api: none
  static Future<List<Map<String, dynamic>>> _pages(
    String path,
    String key,
    Map<String, String> query,
    String context,
  ) async {
    final items = <Map<String, dynamic>>[];
    while (true) {
      final json = await _get(path, {
        ...query,
        'offset': '${items.length}',
        'limit': '$_pageSize',
      }, context);
      final page = _list(json[key]).toList();
      items.addAll(page);
      final total = (json['total'] as num?)?.toInt() ?? 0;
      if (page.isEmpty || items.length >= total) return items;
    }
  }

  /// GETs [path] with [query] and reads the JSON object it answers.
  ///
  /// api: none
  static Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
    String context,
  ) async {
    final response = await instance.authenticatedGet(
      apiBaseUri.replace(
        path: path,
        queryParameters: query.isEmpty ? null : query,
      ),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, context);
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static Iterable<Map<String, dynamic>> _list(Object? value) =>
      (value is List ? value : const <Object?>[])
          .whereType<Map<String, dynamic>>();
}
