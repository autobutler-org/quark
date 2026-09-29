import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/quark_menu_entry.dart';
import 'show_quark_menu.dart';

/// The three-dot button on an item that opens its menu through
/// `showQuarkMenu`, dropping down from the button.
///
/// Give the item's long press and right-click the same [entries] and all three
/// open one menu (#2267). With no row in [entries] the button is disabled.
///
/// ```dart
/// QuarkMenuButton(
///   key: ValueKey('user_menu_$name'),
///   tooltip: 'Actions for $name',
///   entries: [QuarkMenuEntry(label: 'Delete', onSelected: onDelete)],
/// );
/// ```
class QuarkMenuButton extends StatelessWidget {
  /// Creates the button over [entries].
  const QuarkMenuButton({
    required this.entries,
    this.tooltip = 'More',
    this.iconSize,
    super.key,
  });

  /// The rows the menu offers, in order.
  final List<QuarkMenuEntry> entries;

  /// Read on hover and by screen readers.
  final String tooltip;

  /// The glyph's size, or null for the theme's.
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = entries.any((e) => !e.isDivider);
    return IconButton(
      icon: const Icon(QuarkIcons.more_vert),
      iconSize: iconSize,
      tooltip: tooltip,
      onPressed: enabled
          ? () => showQuarkMenu(
              context,
              position: quarkMenuAnchor(context),
              entries: entries,
            )
          : null,
    );
  }
}
