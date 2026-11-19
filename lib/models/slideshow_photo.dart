/// One photo a slideshow can show: a Quark photo addressed by [relPath] and
/// [serial], or a photo on this device, which has no [relPath].
class SlideshowPhoto {
  const SlideshowPhoto({
    required this.id,
    required this.name,
    this.relPath,
    this.serial,
  });

  /// The photo's identity in the grid it came from.
  final String id;

  /// The file name, which says whether it is a video the slideshow skips.
  final String name;

  /// The photo's path within its device's files, or null for a photo on
  /// this device.
  final String? relPath;

  /// The device holding a Quark photo; null or empty for the internal drive.
  final String? serial;
}
