import 'package:flutter/widgets.dart';

/// One installed plugin's row in the drawer, below the built-in pages.
///
/// The caller resolves [icon] from whatever the plugin declared; the package
/// never reads a plugin manifest.
class DrawerPluginItem {
  /// Creates the row for the plugin [id], labeled [label] beside [icon].
  const DrawerPluginItem({
    required this.id,
    required this.label,
    required this.icon,
  });

  /// The plugin's id, which names its row's key and is handed back on a tap.
  final String id;

  /// The text of the row.
  final String label;

  /// The glyph at the start of the row.
  final IconData icon;
}
