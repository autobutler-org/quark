import 'dart:convert';

import 'package:quark/models/job.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// The music library API under `/api/v0/music` (#3280): tracks, albums,
/// artists and genres built from the audio files on the Quark, a tag search,
/// the library's status, the admin's rescan, and the signed-in user's play
/// history (#3284).
///
/// Every listing is filtered by the signed-in user's access on the Quark, so
/// what comes back is what this user may open. Cover art is the thumbnail
/// endpoint asked for a track's path ([coverUrl]).
class MusicService with AuthenticatedService {
  MusicService._();
  static final MusicService instance = MusicService._();

  /// The largest page the Quark returns.
  static const maxLimit = 200;

  /// One page of tracks. [albumKey], [artist] and [genre] narrow it; an
  /// empty [artist] or [genre] names the untagged ones, so pass null to not
  /// filter. [sort] is one of `title`, `artist`, `album`, `year` and
  /// `added`; null keeps album order (disc, then track number).
  static Future<MusicListing<MusicTrack>> listTracks({
    String? albumKey,
    String? artist,
    String? genre,
    String? sort,
    bool descending = false,
    int offset = 0,
    int limit = maxLimit,
  }) async {
    final body = await _get('tracks', 'list music tracks', {
      'albumKey': ?albumKey,
      'artist': ?artist,
      'genre': ?genre,
      'sort': ?sort,
      if (descending) 'order': 'desc',
      'offset': '$offset',
      'limit': '$limit',
    });
    return _page(body, 'tracks', MusicTrack.fromJson);
  }

  /// One page of albums, by title; only [artist]'s when it is non-null.
  static Future<MusicListing<MusicAlbum>> listAlbums({
    String? artist,
    int offset = 0,
    int limit = maxLimit,
  }) async {
    final body = await _get('albums', 'list music albums', {
      'artist': ?artist,
      'offset': '$offset',
      'limit': '$limit',
    });
    return _page(body, 'albums', MusicAlbum.fromJson);
  }

  /// One page of album artists, by name.
  static Future<MusicListing<MusicArtist>> listArtists({
    int offset = 0,
    int limit = maxLimit,
  }) async {
    final body = await _get('artists', 'list music artists', {
      'offset': '$offset',
      'limit': '$limit',
    });
    return _page(body, 'artists', MusicArtist.fromJson);
  }

  /// Every genre, by name.
  static Future<List<MusicGenre>> listGenres() async {
    final body = await _get('genres', 'list music genres', const {});
    return _list(body['genres'], MusicGenre.fromJson);
  }

  /// The tracks whose tags match [query], best first. The Quark answers 501
  /// on PostgreSQL, where music search is not built yet (#2958).
  static Future<List<MusicSearchHit>> search(String query) async {
    final body = await _get('search', 'search music', {'q': query});
    return _list(body['results'], MusicSearchHit.fromJson);
  }

  /// How many tracks the user can see, and whether a scan is running.
  static Future<MusicStatus> status() async =>
      MusicStatus.fromJson(await _get('status', 'music status', const {}));

  /// Queues a full rescan of every device (admin only) and returns its job.
  static Future<Job> rescan() async {
    final response = await instance.authenticatedPost(
      apiBaseUri.replace(path: '/api/v0/music/rescan'),
    );
    if (response.statusCode != 202 && response.statusCode != 200) {
      throw ApiException(response.statusCode, 'rescan music');
    }
    return Job.fromJson(_object(jsonDecode(response.body)));
  }

  /// Counts one play of the track at [relPath] on [serial] for the signed-in
  /// user. The Quark answers 404 for a file that is not in the library.
  static Future<void> recordPlay(String relPath, {String serial = ''}) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.replace(path: '/api/v0/music/plays'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'serial': serial, 'relPath': relPath}),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException(response.statusCode, 'record music play');
    }
  }

  /// The tracks the signed-in user has played: most recent first for
  /// `recent`, most played first for `most`.
  static Future<List<MusicPlay>> history({
    String sort = 'recent',
    int limit = 10,
  }) async {
    final body = await _get('history', 'music history', {
      'sort': sort,
      'limit': '$limit',
    });
    return _list(body['tracks'], MusicPlay.fromJson);
  }

  /// The cover thumbnail for the track at [relPath] on [serial]. The Quark
  /// answers 404 when the track has no cover, and the caller draws a
  /// placeholder.
  static Uri coverUrl(String relPath, {String serial = ''}) =>
      FilesService.constructThumbnailUrl(relPath, serial: serial);

  static Future<Map<String, dynamic>> _get(
    String path,
    String context,
    Map<String, String> query,
  ) async {
    final response = await instance.authenticatedGet(
      apiBaseUri.replace(
        path: '/api/v0/music/$path',
        queryParameters: query.isEmpty ? null : query,
      ),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, context);
    }
    return _object(jsonDecode(response.body));
  }

  static Map<String, dynamic> _object(Object? decoded) =>
      decoded is Map<String, dynamic> ? decoded : const {};

  static MusicListing<T> _page<T>(
    Map<String, dynamic> body,
    String field,
    T Function(Map<String, dynamic>) fromJson,
  ) => MusicListing(
    items: _list(body[field], fromJson),
    total: (body['total'] as num?)?.toInt() ?? 0,
  );

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) => [
    for (final json
        in (raw is List ? raw : const <Object?>[])
            .whereType<Map<String, dynamic>>())
      fromJson(json),
  ];
}
