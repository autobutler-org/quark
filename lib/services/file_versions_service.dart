import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/file_version.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The file version history API: `/api/v0/versions`. Every call addresses one
/// file by its files-relative path; versions exist on the internal drive
/// only, so there is no device serial.
///
/// A refusal throws [ApiException] rather than going through [throwApiError]:
/// the handlers answer with the Go error's text, which is not copy for a
/// user, so the status code is what [Errors] reads.
class FileVersionsService with AuthenticatedService {
  FileVersionsService._();
  static final FileVersionsService instance = FileVersionsService._();

  /// The saved versions of the file at [path], newest first.
  static Future<List<FileVersion>> list(String path) async {
    final response = await instance.authenticatedGet(_uri('', path));
    _check(response, 'list file versions');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['versions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FileVersion.fromJson)
        .toList(growable: false);
  }

  /// The bytes of version [id] of the file at [path]. The whole version is
  /// held in memory, so the caller bounds what it asks for by
  /// [FileVersion.size].
  static Future<Uint8List> content(String path, String id) async {
    final response = await instance.authenticatedGet(
      _uri('/$id/content', path),
    );
    _check(response, 'load a file version');
    return response.bodyBytes;
  }

  /// Puts the file at [path] back to version [id]. The Quark saves what the
  /// file held as a "Before restore" version first, and returns that backup.
  static Future<FileVersion> restore(String path, String id) async {
    final response = await instance.authenticatedPost(
      _uri('/$id/restore', path),
    );
    _check(response, 'restore a file version');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return FileVersion.fromJson(
      body['backup'] as Map<String, dynamic>? ?? const {},
    );
  }

  static Uri _uri(String suffix, String path) => apiBaseUri.replace(
    path: '/api/v0/versions$suffix',
    queryParameters: {'path': path},
  );

  static void _check(http.Response response, String context) =>
      throwUnlessOk(response, context, serverText: false);
}
