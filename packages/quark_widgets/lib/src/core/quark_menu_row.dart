import 'package:material_ui/material_ui.dart';

import '../models/quark_menu_entry.dart';
import '../theme/quark_tokens.dart';
import 'quark_loader.dart';
import 'quark_menu_button.dart';
import 'show_quark_menu.dart';

/// One row of a list whose actions sit in a menu: a leading glyph, a one-line
/// title, a muted one-line subtitle, and a trailing [QuarkMenuButton] that a
/// right-click on the row opens too (#2276).
///
/// While [busy], a [QuarkLoader] takes the button's place and the right-click
/// does nothing. With no [entries] the row has no trailing widget. The caller
/// decides the words, the glyph, and which actions exist; the row owns the
/// layout.
///
/// Key prefixes: none of its own. The caller's `key` sits on the row and
/// [menuKey] on the menu button, and each entry carries its own key.
///
/// ```dart
/// QuarkMenuRow(
///   key: ValueKey('group_row_$id'),
///   menuKey: ValueKey('group_menu_$id'),
///   leading: const Icon(QuarkIcons.group_outlined),
///   title: name,
///   subtitle: '3 members',
///   menuTooltip: 'Actions for $name',
///   entries: [QuarkMenuEntry(label: 'Rename', onSelected: onRename)],
/// );
/// ```
class QuarkMenuRow extends StatelessWidget {
  /// Creates a row titled [title] offering [entries].
  const QuarkMenuRow({
    required this.title,
    this.leading,
    this.subtitle,
    this.busy = false,
    this.entries = const [],
    this.menuTooltip = 'More',
    this.menuKey,
    super.key,
  });

  /// The glyph before the title, or null for none.
  final Widget? leading;

  /// The row's name, cut to one line.
  final String title;

  /// The muted line under the title, cut to one line. Null leaves it out.
  final String? subtitle;

  /// Whether an action on this row is in flight. Shows a loader in place of
  /// the menu and turns the right-click off.
  final bool busy;

  /// The actions on offer, in order. Each entry's `onSelected` fires when it
  /// is picked from the button or the right-click menu. Empty leaves the menu
  /// out.
  final List<QuarkMenuEntry> entries;

  /// The menu button's tooltip, read on hover and by screen readers.
  final String menuTooltip;

  /// The key on the menu button, so a `.probe` script can tap it.
  final Key? menuKey;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final hasMenu = !busy && entries.isNotEmpty;
    final subtitle = this.subtitle;

    return GestureDetector(
      onSecondaryTapUp: hasMenu
          ? (details) => showQuarkMenu(
              context,
              position: details.globalPosition,
              entries: entries,
            )
          : null,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.mutedForeground),
              ),
        trailing: busy
            ? const QuarkLoader(size: 24)
            : hasMenu
            ? QuarkMenuButton(
                key: menuKey,
                tooltip: menuTooltip,
                entries: entries,
              )
            : null,
      ),
    );
  }
}
