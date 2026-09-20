import 'package:flutter/material.dart';

import '../layout/quark_toolbar.dart';
import '../models/file_shortcut.dart';
import '../theme/quark_tokens.dart';

/// A row of one-tap destinations for the file browser, such as a person's own
/// files or the folders their groups share.
///
/// A member's files sit under scaffolding folders they can enter but not use,
/// so reaching them by walking the tree takes two clicks through a folder that
/// only exists as a waypoint. The bar is how they skip it.
///
/// Data in, callbacks out: the bar knows nothing about paths. Each shortcut
/// carries an [FileShortcut.id] and [onSelected] hands that id back. An empty
/// [shortcuts] renders nothing at all, so a caller with none to offer can
/// place the bar unconditionally.
///
/// The chips go through a [QuarkToolbar] that scrolls sideways, so a narrow
/// phone shows the first of them and scrolls to the rest rather than
/// overflowing.
///
/// Key prefixes: `file_shortcut_<id>` on each chip, so a `.probe` script can
/// write `tap #file_shortcut_my_files`.
///
/// ```dart
/// FileShortcutBar(
///   shortcuts: const [
///     FileShortcut(id: 'my_files', label: 'My files', icon: Icons.home),
///   ],
///   onSelected: controller.openShortcut,
/// );
/// ```
class FileShortcutBar extends StatelessWidget {
  /// Creates the bar over [shortcuts].
  const FileShortcutBar({
    required this.shortcuts,
    required this.onSelected,
    super.key,
  });

  /// The destinations, rendered in the order they are given.
  final List<FileShortcut> shortcuts;

  /// Called with the [FileShortcut.id] of the chip that was tapped.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (shortcuts.isEmpty) {
      return const SizedBox.shrink();
    }

    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: QuarkToolbar(
        overflow: QuarkToolbarOverflow.scroll,
        actions: [
          for (final shortcut in shortcuts)
            ActionChip(
              key: ValueKey('file_shortcut_${shortcut.id}'),
              avatar: Icon(shortcut.icon, size: 18),
              label: Text(shortcut.label),
              onPressed: () => onSelected(shortcut.id),
            ),
        ],
      ),
    );
  }
}
