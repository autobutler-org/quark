/// Represents a paginated response from the /api/v0/photos endpoint.
class PaginatedPhotosResponse {
  final List<PhotoItem> photos;
  final int total;
  final int offset;
  final int limit;

  const PaginatedPhotosResponse({
    required this.photos,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory PaginatedPhotosResponse.fromJson(Map<String, dynamic> json) {
    final photosList =
        (json['photos'] as List<dynamic>?)
            ?.map((item) => PhotoItem.fromJson(item as Map<String, dynamic>))
            .toList(growable: false) ??
        const <PhotoItem>[];

    return PaginatedPhotosResponse(
      photos: photosList,
      total: json['total'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      limit: json['limit'] as int? ?? 50,
    );
  }
}

/// A photo returned by the paginated photos endpoint.
class PhotoItem {
  final String relPath;
  final String fileName;
  final int size;
  final int mtime;
  final String serial;
  final bool hasLiveVideo;

  /// When the photo was taken, from its EXIF data, in Unix seconds. Sent only
  /// under the date-taken sort, and only once the Quark has read it (#2592).
  final int? takenAt;

  const PhotoItem({
    required this.relPath,
    required this.fileName,
    required this.size,
    required this.mtime,
    required this.serial,
    this.hasLiveVideo = false,
    this.takenAt,
  });

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      relPath: json['relPath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      mtime: json['mtime'] as int? ?? 0,
      serial: json['serial'] as String? ?? '',
      hasLiveVideo: json['hasLiveVideo'] as bool? ?? false,
      takenAt: json['takenAt'] as int?,
    );
  }
}
