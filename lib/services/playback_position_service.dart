import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/playback_position.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The video resume API: `/api/v0/playback`. Every call addresses one file by
/// its files-relative path and its device's serial, where a null or empty
/// serial is the internal drive. The state is kept per signed-in user.
///
/// A refusal throws [ApiException]; the status code is what [Errors] reads.
class PlaybackPositionService with AuthenticatedService {
  PlaybackPositionService._();
  static final PlaybackPositionService instance = PlaybackPositionService._();

  static const _path = '/api/v0/playback';
  static const _json = {'Content-Type': 'application/json'};

  /// The stored state of the video at [relPath]; a zero state when the Quark
  /// holds nothing for it.
  ///
  /// api: GET /api/v0/playback
  static Future<PlaybackPosition> get(String relPath, {String? serial}) async {
    final response = await instance.authenticatedGet(
      apiBaseUri.replace(
        path: _path,
        queryParameters: {'relPath': relPath, 'deviceSerial': serial ?? ''},
      ),
    );
    return _parse(response, 'load the playback position');
  }

  /// Stores how far playback has reached and returns the state as stored. The
  /// Quark decides whether [position] is near enough the end to count as
  /// watched, so the caller adopts what comes back.
  ///
  /// api: PUT /api/v0/playback
  static Future<PlaybackPosition> save(
    String relPath, {
    String? serial,
    required Duration position,
    required Duration duration,
  }) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.replace(path: _path),
      headers: _json,
      body: jsonEncode({
        'relPath': relPath,
        'deviceSerial': serial ?? '',
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      }),
    );
    return _parse(response, 'save the playback position');
  }

  /// Marks the video watched or unwatched and returns the state as stored.
  /// Unwatched clears the stored position too.
  ///
  /// api: PUT /api/v0/playback/watched
  static Future<PlaybackPosition> setWatched(
    String relPath, {
    String? serial,
    required bool watched,
  }) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.replace(path: '$_path/watched'),
      headers: _json,
      body: jsonEncode({
        'relPath': relPath,
        'deviceSerial': serial ?? '',
        'watched': watched,
      }),
    );
    return _parse(response, 'set the watched state');
  }

  static PlaybackPosition _parse(http.Response response, String context) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to $context');
    }
    return PlaybackPosition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
