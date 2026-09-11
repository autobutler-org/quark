import 'package:flutter/widgets.dart';

/// One choice in a `PhotoCategoryList`: which photos to show, what to call
/// them, and how many there are.
@immutable
class PhotoCategoryEntry {
  /// Creates a category entry.
  const PhotoCategoryEntry({
    required this.id,
    required this.label,
    required this.count,
    required this.icon,
  });

  /// The category's stable identifier, and what the list's callbacks carry.
  final String id;

  /// What the list calls the category.
  final String label;

  /// How many photos the category holds.
  final int count;

  /// The glyph beside the label.
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoCategoryEntry &&
          other.id == id &&
          other.label == label &&
          other.count == count &&
          other.icon == icon;

  @override
  int get hashCode => Object.hash(id, label, count, icon);
}
