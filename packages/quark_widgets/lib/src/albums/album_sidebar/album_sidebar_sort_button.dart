import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/album_sort.dart';
import '../../theme/quark_tokens.dart';

/// The sort button in an `AlbumSidebar` header: a small icon that opens a menu
/// of every [AlbumSort], with a check beside [sort].
///
/// Key prefixes: `album_sort` on the button, `album_sort_option_<id>` on each
/// menu row, where `<id>` is [AlbumSort.id].
///
/// ```dart
/// AlbumSidebarSortButton(
///   sort: controller.albumSort,
///   onChanged: controller.setAlbumSort,
/// );
/// ```
class AlbumSidebarSortButton extends StatelessWidget {
  /// Creates the button showing [sort] as the current choice.
  const AlbumSidebarSortButton({
    required this.sort,
    required this.onChanged,
    super.key,
  });

  /// The order the albums are listed in now.
  final AlbumSort sort;

  /// Called with the order the user picked from the menu.
  final ValueChanged<AlbumSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      menuChildren: [
        for (final option in AlbumSort.values)
          MenuItemButton(
            key: ValueKey('album_sort_option_${option.id}'),
            trailingIcon: option == sort
                ? Icon(
                    QuarkIcons.check_rounded,
                    size: 16,
                    color: tokens.primary,
                  )
                : null,
            onPressed: () => onChanged(option),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('album_sort'),
        icon: const Icon(QuarkIcons.sort, size: 16),
        tooltip: 'Sort albums',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
