import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Photos page's second bar row: what the grid shows on the left, and the
/// way into Duplicates on the right (#2576).
///
/// Duplicates used to be a copy icon in the top row whose only name was a
/// hover tooltip, which a touch screen never shows. Here it is a chip reading
/// "Duplicates", and below `QuarkAppBarBottom.collapseBreakpoint` a menu
/// labeled "Tools" holding it, so the word is on screen at every width.
///
/// Key prefixes: `photos_duplicates` on the chip, `app_bar_bottom_menu` on
/// the menu, `photos_menu_duplicates` on its item.
class PhotosBarBottom extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the row reading [title], opening Duplicates with [onDuplicates].
  const PhotosBarBottom({
    required this.title,
    required this.onDuplicates,
    super.key,
  });

  /// What the grid shows, such as "All photos".
  final String title;

  /// Opens the duplicates review.
  final VoidCallback onDuplicates;

  static const _tooltip = 'Find photos saved more than once';

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return QuarkAppBarBottom(
      lead: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
        ),
      ),
      actions: [
        QuarkBarChip(
          key: const ValueKey('photos_duplicates'),
          icon: QuarkIcons.content_copy,
          label: 'Duplicates',
          tooltip: _tooltip,
          keepLabel: true,
          onPressed: onDuplicates,
        ),
      ],
      menuLabel: 'Tools',
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('photos_menu_duplicates'),
          leadingIcon: const Icon(QuarkIcons.content_copy),
          onPressed: onDuplicates,
          child: const Text('Duplicates'),
        ),
      ],
    );
  }
}
