import 'package:flutter/widgets.dart';

/// One destination a `FileShortcutBar` offers.
///
/// A shortcut is a label and a glyph with an [id] the caller recognizes; where
/// it leads is the caller's business, so the bar never holds a path.
class FileShortcut {
  /// Creates a shortcut labeled [label], identified by [id].
  const FileShortcut({
    required this.id,
    required this.label,
    required this.icon,
  });

  /// What the bar hands back when this shortcut is tapped, and the suffix of
  /// its key. Stable and unique within one bar.
  final String id;

  /// The words on the chip.
  final String label;

  /// The glyph before the label.
  final IconData icon;
}
