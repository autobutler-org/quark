import 'package:flutter/foundation.dart';

/// One copy of a photo in a duplicate group, as the widgets need it: an id,
/// its file name, and where it lives, which is what tells two copies apart.
@immutable
class DuplicatePhotoItem {
  /// Creates a copy.
  const DuplicatePhotoItem({
    required this.id,
    required this.name,
    required this.location,
  });

  /// Stable and unique across every group, and what selection is matched on.
  final String id;

  /// The file name.
  final String name;

  /// Where the file is, such as "Camera/2024" or "USB drive · Backups".
  final String location;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicatePhotoItem &&
          other.id == id &&
          other.name == name &&
          other.location == location;

  @override
  int get hashCode => Object.hash(id, name, location);
}
