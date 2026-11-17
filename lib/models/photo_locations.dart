import 'package:flutter/foundation.dart';

/// One photo the Locations view places on its map (#3557), at the GPS
/// position read from its own EXIF data. Read from
/// `GET /api/v0/photos/locations`.
@immutable
class PhotoLocationPoint {
  /// Creates a point.
  const PhotoLocationPoint({
    required this.serial,
    required this.relPath,
    required this.fileName,
    required this.latitude,
    required this.longitude,
    this.takenAt,
    required this.modified,
  });

  /// Reads one entry of the response's `points`.
  factory PhotoLocationPoint.fromJson(Map<String, dynamic> json) {
    final taken = (json['takenAt'] as num?)?.toInt() ?? 0;
    return PhotoLocationPoint(
      serial: json['serial'] as String? ?? '',
      relPath: json['relPath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0,
      takenAt: taken == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(taken * 1000, isUtc: true),
      modified: DateTime.fromMillisecondsSinceEpoch(
        ((json['mtime'] as num?)?.toInt() ?? 0) * 1000,
        isUtc: true,
      ),
    );
  }

  /// The drive the photo is on, empty for the internal one.
  final String serial;

  /// The photo's path on that drive.
  final String relPath;

  /// The photo's file name.
  final String fileName;

  /// Where it was taken, in degrees.
  final double latitude;
  final double longitude;

  /// When it was taken, from its EXIF, or null when that is unknown.
  final DateTime? takenAt;

  /// When the file was last written, the date a photo with no [takenAt]
  /// goes by.
  final DateTime modified;

  /// The photo's identity across drives, for selection and keys.
  String get id => '$serial:$relPath';

  /// The date the photo sorts and is grouped by.
  DateTime get date => takenAt ?? modified;
}

/// Where the caller's photos were taken, and how the rest of the library
/// stands: `GET /api/v0/photos/locations` (#3557).
@immutable
class PhotoLocations {
  /// Creates the result.
  const PhotoLocations({
    required this.points,
    required this.total,
    required this.located,
    required this.unlocated,
    required this.pending,
  });

  /// Reads the response body.
  factory PhotoLocations.fromJson(Map<String, dynamic> json) => PhotoLocations(
    points: [
      for (final entry in json['points'] as List? ?? const [])
        PhotoLocationPoint.fromJson(entry as Map<String, dynamic>),
    ],
    total: (json['total'] as num?)?.toInt() ?? 0,
    located: (json['located'] as num?)?.toInt() ?? 0,
    unlocated: (json['unlocated'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
  );

  /// Nothing loaded yet.
  static const empty = PhotoLocations(
    points: [],
    total: 0,
    located: 0,
    unlocated: 0,
    pending: 0,
  );

  /// The placed photos, newest first.
  final List<PhotoLocationPoint> points;

  /// The photos and videos the account can read.
  final int total;

  /// How many are placed; the rest have no position.
  final int located;
  final int unlocated;

  /// How many of the rest the Quark has not read yet, so they may still turn
  /// out to have a position.
  final int pending;
}
