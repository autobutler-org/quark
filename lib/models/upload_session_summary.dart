import 'package:flutter/foundation.dart';

/// Where an [UploadSessionSummary] is in its life, as the Quark reports it.
enum UploadSessionState {
  /// Still taking chunks.
  uploading,

  /// Every byte is in and the file is being saved into place.
  committing,

  /// The file landed.
  completed,

  /// The file can never land.
  failed,

  /// Its owner canceled it.
  canceled,

  /// It sat idle past the Quark's time limit.
  expired,

  /// A state this build of the app does not know, from a newer Quark.
  unknown;

  /// Whether the session is still in flight.
  bool get isActive => this == uploading || this == committing;

  /// The state named [name], or [unknown].
  static UploadSessionState parse(Object? name) => values.firstWhere(
    (state) => state.name == name && state != unknown,
    orElse: () => unknown,
  );
}

/// One resumable upload as `GET /api/v0/files/upload-sessions` describes it.
///
/// [error] is a server diagnostic and is never shown: what a user reads about
/// a failed upload comes from `Errors`.
@immutable
class UploadSessionSummary {
  /// Creates a summary.
  const UploadSessionSummary({
    required this.sessionId,
    required this.fileName,
    required this.state,
    required this.totalSize,
    required this.offset,
    required this.createdAt,
    required this.updatedAt,
    this.rootDir = '',
    this.serial = '',
    this.error = '',
  });

  /// Reads one entry of the listing.
  factory UploadSessionSummary.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse('${json['createdAt']}');
    final updated = DateTime.tryParse('${json['updatedAt']}');
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return UploadSessionSummary(
      sessionId: '${json['sessionId'] ?? ''}',
      fileName: '${json['fileName'] ?? ''}',
      rootDir: '${json['rootDir'] ?? ''}',
      serial: '${json['serial'] ?? ''}',
      state: UploadSessionState.parse(json['state']),
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      createdAt: created ?? updated ?? epoch,
      updatedAt: updated ?? created ?? epoch,
      error: '${json['error'] ?? ''}',
    );
  }

  /// The session's id, the same one the upload protocol uses.
  final String sessionId;

  /// The file being uploaded.
  final String fileName;

  /// The folder it lands in, relative to its drive's root. Empty is the root.
  final String rootDir;

  /// The drive it lands on. Empty is the Quark's own storage.
  final String serial;

  /// Where the session is in its life.
  final UploadSessionState state;

  /// The file's size in bytes.
  final int totalSize;

  /// How many bytes the Quark has committed.
  final int offset;

  /// When the session opened.
  final DateTime createdAt;

  /// When the last chunk landed, or when the session ended.
  final DateTime updatedAt;

  /// The Quark's diagnostic for a failed session. Never shown to a user.
  final String error;
}

/// The caller's upload sessions: in flight oldest first, then ended newest
/// first.
@immutable
class UploadSessionList {
  /// Creates a list.
  const UploadSessionList({this.active = const [], this.finished = const []});

  /// Reads the listing's body.
  factory UploadSessionList.fromJson(Map<String, dynamic> json) {
    List<UploadSessionSummary> read(Object? list) => [
      for (final entry in (list as List?) ?? const [])
        if (entry is Map<String, dynamic>) UploadSessionSummary.fromJson(entry),
    ];
    return UploadSessionList(
      active: read(json['active']),
      finished: read(json['finished']),
    );
  }

  /// Sessions still in flight, oldest first.
  final List<UploadSessionSummary> active;

  /// Sessions that ended recently, newest first.
  final List<UploadSessionSummary> finished;
}
