import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu a user album opens from its `more_vert` button, a long press, or
/// a right-click: rename, new sub-album, delete. It opens at the pointer, the
/// way every item's menu does (#2267).
///
/// The menu closes before an entry fires, so the next dialog opens over the
/// page rather than over the menu.
///
/// Key prefixes: `album_action_rename`, `album_action_new_sub_album` and
/// `album_action_delete` on the entries.
@immutable
class AlbumActionsMenu {
  /// Creates the menu.
  const AlbumActionsMenu({
    required this.onRename,
    required this.onCreateSubAlbum,
    required this.onDelete,
  });

  /// Renames the album.
  final VoidCallback onRename;

  /// Creates an album under this one.
  final VoidCallback onCreateSubAlbum;

  /// Deletes the album.
  final VoidCallback onDelete;

  /// Opens the menu at [globalPosition].
  Future<void> showAt(BuildContext context, Offset globalPosition) =>
      showQuarkMenu(
        context,
        position: globalPosition,
        entries: [
          QuarkMenuEntry(
            key: const ValueKey('album_action_rename'),
            label: 'Rename',
            icon: QuarkIcons.edit_outlined,
            onSelected: onRename,
          ),
          QuarkMenuEntry(
            key: const ValueKey('album_action_new_sub_album'),
            label: 'New sub-album',
            icon: QuarkIcons.create_new_folder_outlined,
            onSelected: onCreateSubAlbum,
          ),
          QuarkMenuEntry(
            key: const ValueKey('album_action_delete'),
            label: 'Delete',
            icon: QuarkIcons.delete_outline,
            destructive: true,
            onSelected: onDelete,
          ),
        ],
      );
}
