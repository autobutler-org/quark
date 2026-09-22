class PhotoExif {
  final DateTime? dateTaken;
  final String? make;
  final String? model;
  final String? lens;
  final double? aperture;
  final String? shutterSpeed;
  final int? iso;
  final double? focalLength;
  final double? latitude;
  final double? longitude;

  const PhotoExif({
    this.dateTaken,
    this.make,
    this.model,
    this.lens,
    this.aperture,
    this.shutterSpeed,
    this.iso,
    this.focalLength,
    this.latitude,
    this.longitude,
  });

  factory PhotoExif.fromJson(Map<String, dynamic> json) => PhotoExif(
    dateTaken: json['dateTaken'] != null
        ? DateTime.tryParse(json['dateTaken'] as String)
        : null,
    make: json['make'] as String?,
    model: json['model'] as String?,
    lens: json['lens'] as String?,
    aperture: (json['aperture'] as num?)?.toDouble(),
    shutterSpeed: json['shutterSpeed'] as String?,
    iso: json['iso'] as int?,
    focalLength: (json['focalLength'] as num?)?.toDouble(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );

  bool get hasCameraInfo =>
      make != null ||
      model != null ||
      lens != null ||
      aperture != null ||
      shutterSpeed != null ||
      iso != null ||
      focalLength != null;

  bool get hasLocation => latitude != null && longitude != null;
}

class AlbumRef {
  final int id;
  final String name;

  const AlbumRef({required this.id, required this.name});

  factory AlbumRef.fromJson(Map<String, dynamic> json) =>
      AlbumRef(id: json['id'] as int, name: json['name'] as String);
}

/// What the Quark knows about one photo: its EXIF data, the albums it is in, its saved rotation, and whether it
/// is a Live Photo.
class PhotoMetadata {
  final String fileName;
  final int fileSize;
  final DateTime mtime;
  final int width;
  final int height;

  /// Server-persisted rotation: 0/1/2/3 × 90° CW.
  final int rotationQuarters;

  /// Whether this photo is in the user's server-side favorites.
  final bool isFavorite;

  final PhotoExif? exif;
  final List<AlbumRef> albums;

  /// Relative path to a companion video (Live Photo). Null if not a Live Photo.
  final String? livePhotoVideoPath;

  const PhotoMetadata({
    required this.fileName,
    required this.fileSize,
    required this.mtime,
    required this.width,
    required this.height,
    this.rotationQuarters = 0,
    this.isFavorite = false,
    this.exif,
    required this.albums,
    this.livePhotoVideoPath,
  });

  bool get isLivePhoto => livePhotoVideoPath != null;

  factory PhotoMetadata.fromJson(Map<String, dynamic> json) => PhotoMetadata(
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int,
    mtime: DateTime.fromMillisecondsSinceEpoch((json['mtime'] as int) * 1000),
    width: json['width'] as int,
    height: json['height'] as int,
    rotationQuarters: (json['rotationQuarters'] as int?) ?? 0,
    isFavorite: (json['isFavorite'] as bool?) ?? false,
    exif: json['exif'] != null
        ? PhotoExif.fromJson(json['exif'] as Map<String, dynamic>)
        : null,
    albums: (json['albums'] as List<dynamic>)
        .map((e) => AlbumRef.fromJson(e as Map<String, dynamic>))
        .toList(),
    livePhotoVideoPath: json['livePhotoVideoPath'] as String?,
  );
}
