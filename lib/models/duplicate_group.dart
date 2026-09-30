/// One group from `GET /api/v0/photos/duplicates` (#1666): photos that are the
/// same file ([isExact]) or only look alike.
class DuplicateGroup {
  const DuplicateGroup({
    required this.isExact,
    required this.photos,
    this.maxDistance,
  });

  /// Whether every copy shares one content hash.
  final bool isExact;

  /// The copies, sorted by device, then path.
  final List<({String deviceSerial, String relPath})> photos;

  /// The largest Hamming distance between any two copies' perceptual hashes,
  /// out of 64 bits: 0 for identical copies, higher the less alike. Null when
  /// the Quark did not send it.
  final int? maxDistance;

  factory DuplicateGroup.fromJson(Map<String, dynamic> json) => DuplicateGroup(
    isExact: json['kind'] == 'exact',
    maxDistance: (json['maxDistance'] as num?)?.toInt(),
    photos: [
      for (final p in (json['photos'] as List<dynamic>? ?? const []))
        (
          deviceSerial:
              (p as Map<String, dynamic>)['deviceSerial'] as String? ?? '',
          relPath: p['relPath'] as String? ?? '',
        ),
    ],
  );
}
