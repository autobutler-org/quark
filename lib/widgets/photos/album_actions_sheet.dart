import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu a long-pressed user album opens: rename, new sub-album, delete.
///
/// Each entry closes the sheet before it fires, so the next dialog opens over
/// the page rather than over the menu.
class AlbumActionsSheet extends StatelessWidget {
  /// Creates the menu.
  const AlbumActionsSheet({
    required this.onRename,
    required this.onCreateSubAlbum,
    required this.onDelete,
    super.key,
  });

  /// Shows the menu as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onRename,
    required VoidCallback onCreateSubAlbum,
    required VoidCallback onDelete,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      builder: (_) => AlbumActionsSheet(
        onRename: onRename,
        onCreateSubAlbum: onCreateSubAlbum,
        onDelete: onDelete,
      ),
    );
  }

  /// Renames the album.
  final VoidCallback onRename;

  /// Creates an album under this one.
  final VoidCallback onCreateSubAlbum;

  /// Deletes the album.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('album_action_rename'),
            leading: const Icon(QuarkIcons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => closeThen(onRename),
          ),
          ListTile(
            key: const ValueKey('album_action_new_sub_album'),
            leading: const Icon(QuarkIcons.create_new_folder_outlined),
            title: const Text('New sub-album'),
            onTap: () => closeThen(onCreateSubAlbum),
          ),
          ListTile(
            key: const ValueKey('album_action_delete'),
            leading: Icon(QuarkIcons.delete_outline, color: error),
            title: Text('Delete', style: TextStyle(color: error)),
            onTap: () => closeThen(onDelete),
          ),
        ],
      ),
    );
  }
}
