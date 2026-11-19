import 'package:flutter/foundation.dart';
import 'package:quark/models/job.dart';

/// An export the Quark has queued, as `POST /api/v0/albums/exports` answers:
/// the job that copies the photos and the new folder it copies them into.
@immutable
class QueuedAlbumExport {
  /// Creates a queued export.
  const QueuedAlbumExport({
    required this.jobId,
    required this.deviceSerial,
    required this.relPath,
  });

  /// The `photo-export` job doing the copying; see [JobKinds.photoExport].
  final int jobId;

  /// The drive the export folder is on. Empty is the internal drive.
  final String deviceSerial;

  /// The new export folder the Quark made inside the chosen folder.
  final String relPath;

  /// Reads the Quark's answer.
  factory QueuedAlbumExport.fromJson(Map<String, dynamic> json) =>
      QueuedAlbumExport(
        jobId: (json['jobId'] as num?)?.toInt() ?? 0,
        deviceSerial: json['deviceSerial'] as String? ?? '',
        relPath: json['relPath'] as String? ?? '',
      );
}

/// Why a photo was not copied, from an export's failure list.
enum AlbumExportFailureReason {
  /// The original was not there to copy.
  missing,

  /// The original was there, but the copy did not work.
  notCopied,
}

/// A photo an export could not copy.
@immutable
class AlbumExportFailure {
  /// Creates a failure.
  const AlbumExportFailure({
    required this.name,
    required this.path,
    required this.reason,
  });

  /// The original's file name, which is what a person recognizes.
  final String name;

  /// Where the copy would have gone, inside the export folder.
  final String path;

  /// Why it was not copied.
  final AlbumExportFailureReason reason;

  /// Reads one entry of the summary's `failures`. A reason this build does
  /// not know reads as [AlbumExportFailureReason.notCopied].
  factory AlbumExportFailure.fromJson(Map<String, dynamic> json) =>
      AlbumExportFailure(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        reason: json['reason'] == 'missing'
            ? AlbumExportFailureReason.missing
            : AlbumExportFailureReason.notCopied,
      );
}

/// What an export has done, as `GET /api/v0/albums/exports/{jobId}` answers.
///
/// An export ends [JobStatus.failed] when any photo was not copied, even when
/// most were, so [isComplete] is the only state that means everything left.
@immutable
class AlbumExportSummary {
  /// Creates a summary.
  const AlbumExportSummary({
    required this.jobId,
    required this.status,
    required this.deviceSerial,
    required this.relPath,
    this.copied = 0,
    this.failures = const [],
    this.moreFailures = 0,
  });

  /// The export's job.
  final int jobId;

  /// The job's status.
  final JobStatus status;

  /// The drive the export folder is on. Empty is the internal drive.
  final String deviceSerial;

  /// The export folder.
  final String relPath;

  /// How many files were copied.
  final int copied;

  /// The photos not copied, up to the Quark's limit.
  final List<AlbumExportFailure> failures;

  /// How many more photos were not copied than [failures] lists.
  final int moreFailures;

  /// Whether the export finished and copied every photo.
  bool get isComplete =>
      status == JobStatus.completed && failures.isEmpty && moreFailures == 0;

  /// How many photos were not copied in all.
  int get failedCount => failures.length + moreFailures;

  /// Reads the Quark's answer.
  factory AlbumExportSummary.fromJson(
    Map<String, dynamic> json,
  ) => AlbumExportSummary(
    jobId: (json['jobId'] as num?)?.toInt() ?? 0,
    status: JobStatus.values.asNameMap()[json['status']] ?? JobStatus.unknown,
    deviceSerial: json['deviceSerial'] as String? ?? '',
    relPath: json['relPath'] as String? ?? '',
    copied: (json['copied'] as num?)?.toInt() ?? 0,
    failures: switch (json['failures']) {
      final List<dynamic> list => List.unmodifiable([
        for (final entry in list)
          if (entry is Map<String, dynamic>) AlbumExportFailure.fromJson(entry),
      ]),
      _ => const [],
    },
    moreFailures: (json['moreFailures'] as num?)?.toInt() ?? 0,
  );
}
