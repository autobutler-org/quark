import 'package:flutter/foundation.dart';

/// Where an [UploadItem] is in its life.
enum UploadItemStatus {
  /// Bytes are arriving.
  uploading,

  /// Every byte has arrived and the file is being saved into place, which on
  /// a slow disk can take minutes.
  finishing,

  /// In flight, but no bytes have arrived for a while.
  stalled,

  /// The file landed.
  completed,

  /// The file can never land, for example because its name was taken.
  failed,

  /// Someone canceled it.
  canceled,

  /// It sat idle so long that the Quark let it go.
  expired,
}

/// One file upload as a `JobList` renders it.
///
/// The caller has already decided everything here, including the transfer
/// rate and the time left, which it works out from successive samples. The
/// list only draws it.
@immutable
class UploadItem {
  /// Creates an upload item.
  const UploadItem({
    required this.id,
    required this.fileName,
    required this.status,
    required this.sentBytes,
    required this.totalBytes,
    this.destination,
    this.bytesPerSecond,
    this.remaining,
    this.canCancel = false,
  });

  /// The upload's stable identifier, and what the list's callback carries.
  final String id;

  /// The name of the file being uploaded.
  final String fileName;

  /// Where the file is going, such as "Photos on USB drive", or null.
  final String? destination;

  /// Where the upload is in its life.
  final UploadItemStatus status;

  /// How many bytes have arrived.
  final int sentBytes;

  /// How big the file is.
  final int totalBytes;

  /// The recent transfer rate, or null when it is not known yet.
  final double? bytesPerSecond;

  /// About how long is left, or null when it is not known.
  final Duration? remaining;

  /// Whether a Cancel action is offered.
  final bool canCancel;
}
