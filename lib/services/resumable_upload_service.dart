import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/upload_conflict.dart';
import 'package:quark/models/upload_session.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/upload_chunk_source.dart';
import 'package:quark/utils/error_text.dart';

/// Where the session endpoints live, under the same `/api/v0` group and behind
/// the same bearer token as every other files call.
///
/// A sibling of `/files/upload` rather than a child of it: the multipart route
/// is registered as a catch-all wildcard over everything under `/files/upload/`
/// (that is how a nested rootDir travels), so the router refuses any static
/// path beneath it.
const String _sessionEndpoint = '/api/v0/files/upload-session';

/// The four verbs of the resumable upload protocol (#1629).
///
/// An interface rather than a bare class so the upload manager can be tested
/// without a server: the manager's job is the chunk loop and the retry
/// accounting, and neither of those needs real HTTP to be wrong in an
/// interesting way.
abstract interface class ResumableUploadClient {
  /// Opens a session for a file about to be sent in chunks.
  ///
  /// Throws an [ApiException] with status 409 when the name is already in use
  /// and [conflict] did not say what to do about it.
  Future<UploadSession> createSession({
    required String rootDir,
    required String fileName,
    required int totalSize,
    String? serial,
    bool overwrite,
    UploadConflictChoice? conflict,
  });

  /// Sends `[start, end)` of [source] to the session.
  ///
  /// [end] is exclusive here and inclusive on the wire — the `Content-Range`
  /// header is RFC 7233 form, and converting once at the boundary beats every
  /// caller remembering which convention it is holding.
  Future<ChunkUploadOutcome> putChunk({
    required String sessionId,
    required UploadChunkSource source,
    required int start,
    required int end,
    required int totalSize,
  });

  /// What the server has committed, or null when the session is gone.
  Future<UploadSessionStatus?> getSession(String sessionId);

  /// Abandons a session and its temp file. Best effort.
  Future<void> deleteSession(String sessionId);
}

class ResumableUploadService
    with AuthenticatedService
    implements ResumableUploadClient {
  ResumableUploadService._();

  static final ResumableUploadService instance = ResumableUploadService._();

  static Uri _sessionUri([String? sessionId]) {
    final path = sessionId == null
        ? _sessionEndpoint
        : '$_sessionEndpoint/${Uri.encodeComponent(sessionId)}';
    return apiBaseUri.resolve(path);
  }

  @override
  Future<UploadSession> createSession({
    required String rootDir,
    required String fileName,
    required int totalSize,
    String? serial,
    bool overwrite = false,
    UploadConflictChoice? conflict,
  }) async {
    final response = await authenticatedPost(
      _sessionUri(),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'rootDir': rootDir,
        'fileName': fileName,
        'totalSize': totalSize,
        if (serial != null && serial.isNotEmpty) 'serial': serial,
        'overwrite': overwrite || conflict == UploadConflictChoice.replace,
        'keepBoth': conflict == UploadConflictChoice.keepBoth,
      }),
    );

    if (response.statusCode != 200) {
      // The status travels rather than the Quark's own words: a 409 is a
      // question for the user, and the caller is what knows how to ask it.
      debugPrint(
        '[resumable_upload_service.dart] Session for $fileName refused '
        '(${response.statusCode}): ${_errorOf(response)}',
      );
      throw ApiException(response.statusCode, 'open an upload session');
    }
    return UploadSession.fromJson(_decode(response));
  }

  @override
  Future<ChunkUploadOutcome> putChunk({
    required String sessionId,
    required UploadChunkSource source,
    required int start,
    required int end,
    required int totalSize,
  }) async {
    final response = await source.putRange(
      uri: _sessionUri(sessionId),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/octet-stream',
        'Content-Range': 'bytes $start-${end - 1}/$totalSize',
      },
      start: start,
      end: end,
    );
    checkUnauthorized(response);

    switch (response.statusCode) {
      case 200:
        return ChunkAccepted.fromJson(_decode(response));
      case 404:
        return const ChunkSessionGone();
      case 409:
        // The server puts the committed offset on the response so a resync
        // costs nothing extra. Falling back to a GET when it is missing keeps
        // this working rather than turning a recoverable case into a failure.
        final offset = int.tryParse(response.headers['x-upload-offset'] ?? '');
        if (offset != null) {
          return ChunkOffsetMismatch(offset: offset);
        }
        final status = await getSession(sessionId);
        return status == null
            ? const ChunkSessionGone()
            : ChunkOffsetMismatch(offset: status.offset);
      default:
        return ChunkRejected(
          statusCode: response.statusCode,
          message: _errorOf(response),
        );
    }
  }

  @override
  Future<UploadSessionStatus?> getSession(String sessionId) async {
    final response = await authenticatedGet(_sessionUri(sessionId));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to read an upload session (${response.statusCode}): '
        '${_errorOf(response)}',
      );
    }
    return UploadSessionStatus.fromJson(_decode(response));
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    try {
      await authenticatedDelete(_sessionUri(sessionId));
    } catch (e) {
      // Best effort by design: the server sweeps expired sessions anyway, and
      // failing to tidy up must not turn a finished upload into a failed one.
      debugPrint(
        '[resumable_upload_service.dart] Could not drop session $sessionId: $e',
      );
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static String _errorOf(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Not JSON. The body itself is the best message available.
    }
    return response.body.isEmpty ? 'no detail' : response.body;
  }
}
