import 'package:flutter/foundation.dart';

import 'duplicate_photo_item.dart';

/// A set of photos that duplicate each other, for `DuplicateGroupList`.
@immutable
class DuplicateGroupItem {
  /// Creates a group of [photos].
  const DuplicateGroupItem({
    required this.id,
    required this.isExact,
    required this.photos,
  });

  /// Stable within one list, and the suffix of the group's key.
  final String id;

  /// Whether every photo is the same file, byte for byte. Otherwise they only
  /// look alike, and may differ in an edit, a crop, or quality.
  final bool isExact;

  /// The copies, two or more.
  final List<DuplicatePhotoItem> photos;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateGroupItem &&
          other.id == id &&
          other.isExact == isExact &&
          listEquals(other.photos, photos);

  @override
  int get hashCode => Object.hash(id, isExact, Object.hashAll(photos));
}
