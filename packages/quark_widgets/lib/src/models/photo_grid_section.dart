import 'package:flutter/foundation.dart';

/// One run of consecutive photos in a `PhotoGrid`, drawn under a header that
/// pins to the top while the run scrolls past, such as "March 2025".
///
/// A section holds a count rather than photos: the grid's photo list stays
/// flat, so every callback still reports an index into it, and the sections
/// split that list in order. The caller decides where runs start and what
/// they are called; the grid only draws them.
@immutable
class PhotoGridSection {
  /// Creates a section of [count] photos headed [label].
  const PhotoGridSection({
    required this.id,
    required this.label,
    required this.count,
  });

  /// Unique within one grid, and the suffix of the header's key.
  final String id;

  /// The header text.
  final String label;

  /// How many photos, following the previous section's, belong to this one.
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoGridSection &&
          other.id == id &&
          other.label == label &&
          other.count == count;

  @override
  int get hashCode => Object.hash(id, label, count);
}
