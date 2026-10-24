import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Why the index pass could not read a photo, as the Quark classes it.
enum PhotoIndexFailureReason {
  /// No decoder on the Quark can read it (`undecodable`).
  undecodable,

  /// A camera RAW photo, and no RAW converter is installed
  /// (`missing_converter`).
  missingConverter,

  /// Its header claims more pixels than the Quark will decode (`too_large`).
  tooLarge,

  /// It could not be opened or read at all (`unreadable`).
  unreadable,

  /// A reason this client does not know yet.
  unknown,
}

/// One photo the index pass could not fully read.
class PhotoIndexFailure {
  /// Creates a failure.
  const PhotoIndexFailure({
    required this.serial,
    required this.relPath,
    required this.reason,
  });

  /// The drive's serial, empty for the internal drive.
  final String serial;

  /// The photo's path on that drive.
  final String relPath;

  /// Why it failed.
  final PhotoIndexFailureReason reason;
}

/// The photo library index on this Quark, from
/// `GET /api/v0/photos/index-status` (#3556): the background pass that hashes
/// every photo for duplicate detection and reads its capture date.
class PhotoIndexStatus {
  /// Creates a status.
  const PhotoIndexStatus({
    required this.total,
    required this.hashed,
    required this.datesRead,
    required this.failed,
    required this.failures,
    required this.running,
    required this.paused,
    this.lastRunAt,
  });

  /// Parses the response body.
  factory PhotoIndexStatus.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final value = json[key];
      if (value is! int) throw const FormatException('Invalid index status');
      return value;
    }

    final failures = json['failures'];
    final lastRunAt = json['lastRunAt'];
    return PhotoIndexStatus(
      total: count('total'),
      hashed: count('hashed'),
      datesRead: count('datesRead'),
      failed: count('failed'),
      failures: [
        if (failures is List)
          for (final item in failures)
            if (item is Map<String, dynamic>)
              PhotoIndexFailure(
                serial: item['serial'] as String? ?? '',
                relPath: item['relPath'] as String? ?? '',
                reason: _reason(item['reason']),
              ),
      ],
      lastRunAt: lastRunAt is String && lastRunAt.isNotEmpty
          ? DateTime.parse(lastRunAt)
          : null,
      running: json['running'] == true,
      paused: json['paused'] == true,
    );
  }

  /// The photos in the library when the pass last listed it.
  final int total;

  /// The photos duplicate detection can compare.
  final int hashed;

  /// The photos whose capture date has been read.
  final int datesRead;

  /// Every photo the pass could not fully read.
  final int failed;

  /// The first of those, at most 500.
  final List<PhotoIndexFailure> failures;

  /// When a pass last finished, or null if none has since the Quark started.
  final DateTime? lastRunAt;

  /// Whether a pass is under way, paused or not.
  final bool running;

  /// Whether the pass is held, or will hold when it starts.
  final bool paused;
}

PhotoIndexFailureReason _reason(Object? raw) => switch (raw) {
  'undecodable' => PhotoIndexFailureReason.undecodable,
  'missing_converter' => PhotoIndexFailureReason.missingConverter,
  'too_large' => PhotoIndexFailureReason.tooLarge,
  'unreadable' => PhotoIndexFailureReason.unreadable,
  _ => PhotoIndexFailureReason.unknown,
};

/// The admin-only photo library index API (#3556):
/// `GET /api/v0/photos/index-status`, and `POST /api/v0/photos/index/pause`
/// and `/resume`, each answering with the status. A non-admin gets a 403.
class PhotoIndexService with AuthenticatedService {
  PhotoIndexService._();

  /// The shared service.
  static final PhotoIndexService instance = PhotoIndexService._();

  /// The index status.
  static Future<PhotoIndexStatus> fetchStatus() async => _read(
    await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/photos/index-status'),
    ),
    'load the photo index status',
  );

  /// Holds the pass before its next photo.
  static Future<PhotoIndexStatus> pause() async => _read(
    await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/photos/index/pause'),
    ),
    'pause indexing',
  );

  /// Lets a paused pass carry on.
  static Future<PhotoIndexStatus> resume() async => _read(
    await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/photos/index/resume'),
    ),
    'resume indexing',
  );

  static PhotoIndexStatus _read(http.Response response, String context) {
    final status = response.statusCode;
    if (status < 200 || status >= 300) throw ApiException(status, context);
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid index status');
    }
    return PhotoIndexStatus.fromJson(body);
  }
}
