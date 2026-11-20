import 'dart:convert';

import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The music library API under `/api/v0/music`: the albums the signed-in
/// user can read, and an album's tracks in playing order.
class MusicService with AuthenticatedService {
  MusicService._();
  static final MusicService instance = MusicService._();

  /// The most the Quark answers in one page.
  static const int _pageSize = 200;

  /// Lists the music albums, ordered by album artist and title: the first
  /// [_pageSize], which is as many as a picker shows.
  ///
  /// api: GET /api/v0/music/albums
  static Future<List<MusicAlbum>> listAlbums() async {
    final json = await _get('/api/v0/music/albums', {
      'limit': '$_pageSize',
    }, 'list music albums');
    return [
      for (final album in _list(json['albums'])) MusicAlbum.fromJson(album),
    ];
  }

  /// Lists the tracks of the album [albumKey] in album order: disc, then
  /// track.
  ///
  /// api: GET /api/v0/music/tracks
  static Future<List<MusicTrack>> listAlbumTracks(String albumKey) async {
    final json = await _get('/api/v0/music/tracks', {
      'albumKey': albumKey,
      'limit': '$_pageSize',
    }, 'list album tracks');
    return [
      for (final track in _list(json['tracks'])) MusicTrack.fromJson(track),
    ];
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
      apiBaseUri.replace(path: path, queryParameters: query),
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
