import 'dart:convert';

import 'package:quark/models/upload_session_summary.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The account's resumable uploads as the Quark sees them:
/// `GET /api/v0/files/upload-sessions`, and `DELETE` on one session to cancel
/// it from any device.
///
/// A refusal throws [ApiException]: a session's error text is a diagnostic,
/// so the status code is what [Errors] reads.
class UploadSessionsService with AuthenticatedService {
  UploadSessionsService._();

  /// The one instance.
  static final UploadSessionsService instance = UploadSessionsService._();

  /// The caller's sessions, in flight and recently ended.
  static Future<UploadSessionList> listSessions() async {
    final uri = apiBaseUri.resolve('/api/v0/files/upload-sessions');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list upload sessions');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? UploadSessionList.fromJson(decoded)
        : const UploadSessionList();
  }

  /// Cancels session [sessionId] and drops what it had staged. A 404 means it
  /// had already ended.
  static Future<void> cancelSession(String sessionId) async {
    final uri = apiBaseUri.resolve(
      '/api/v0/files/upload-session/${Uri.encodeComponent(sessionId)}',
    );
    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to cancel upload');
    }
  }

  /// Whether [sessionId] ended because someone canceled it. False when the
  /// Quark cannot say, so a caller that guesses wrong only retries.
  static Future<bool> wasCanceled(String sessionId) async {
    try {
      final list = await listSessions();
      return list.finished.any(
        (s) =>
            s.sessionId == sessionId && s.state == UploadSessionState.canceled,
      );
    } catch (_) {
      return false;
    }
  }
}
