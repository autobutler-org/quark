import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu a user album opens from its `more_vert` button, a long press, or
/// a right-click: rename, new sub-album, export, keep on this phone, delete.
/// It opens at the pointer, the way every item's menu does (#2267).
///
/// The menu closes before an entry fires, so the next dialog opens over the
/// page rather than over the menu.
///
/// Key prefixes: `album_action_rename`, `album_action_new_sub_album`,
/// `album_action_export`, `album_action_keep_on_phone` and
/// `album_action_delete` on the entries.
@immutable
class AlbumActionsMenu {
  /// Creates the menu.
  const AlbumActionsMenu({
    required this.onRename,
    required this.onCreateSubAlbum,
    required this.onDelete,
    this.onExport,
    this.onKeepOnPhone,
    this.isKeptOnPhone = false,
  });

  /// Renames the album.
  final VoidCallback onRename;

  /// Creates an album under this one.
  final VoidCallback onCreateSubAlbum;

  /// Deletes the album.
  final VoidCallback onDelete;

  /// Exports the album as copied files (#3501). Null leaves Export out.
  final VoidCallback? onExport;

  /// Keeps the album on this phone for offline viewing, or stops keeping it
  /// when [isKeptOnPhone] (#4222). Null leaves the entry out, as on the web.
  final VoidCallback? onKeepOnPhone;

  /// Whether the album is already kept on this phone, which turns the keep
  /// entry into one that stops keeping it.
  final bool isKeptOnPhone;

  /// Opens the menu at [globalPosition].
  Future<void> showAt(BuildContext context, Offset globalPosition) {
    final onExport = this.onExport;
    final onKeepOnPhone = this.onKeepOnPhone;
    return showQuarkMenu(
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
        if (onExport != null)
          QuarkMenuEntry(
            key: const ValueKey('album_action_export'),
            label: 'Export…',
            icon: QuarkIcons.download_outlined,
            onSelected: onExport,
          ),
        if (onKeepOnPhone != null)
          QuarkMenuEntry(
            key: const ValueKey('album_action_keep_on_phone'),
            label: isKeptOnPhone
                ? 'Stop keeping on this phone'
                : 'Keep on this phone',
            icon: isKeptOnPhone
                ? QuarkIcons.cloud_off_outlined
                : QuarkIcons.smartphone,
            onSelected: onKeepOnPhone,
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
}
