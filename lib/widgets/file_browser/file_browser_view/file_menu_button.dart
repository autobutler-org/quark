import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark_icons/quark_icons.dart';

/// Runs one of the row's menu entries. The [BuildContext] is the one the menu
/// item was built with, which is what the caller checks for mounting before it
/// touches the tree.
typedef FileMenuActionDispatch =
    void Function(BuildContext context, FileNode item, FileMenuAction action);

/// The "more" menu on one file or folder, shared by the list and grid views.
///
/// Offers the entries in [menuActions] that make sense for [item]: nothing
/// that changes or shares a file inside an archive, Extract only on an
/// archive, Navigate to folder only in search results, and no Move/Rename or
/// Delete on the `users` or `groups` folder, a home folder, or a group's
/// folder itself unless the viewer is an admin. Share is hidden on the `users`
/// and `groups` folders for everyone, admins included: access is additive down
/// the tree, so a grant there would expose every home or every group folder at
/// once, and the Quark refuses it (#2016).
class FileMenuButton extends StatelessWidget {
  const FileMenuButton({
    required this.item,
    required this.menuActions,
    required this.extractingPaths,
    required this.inArchive,
    required this.isSearchMode,
    required this.onDispatchMenuAction,
    this.isAdmin = false,
    this.onNavigateToFolder,
    super.key,
  });

  final FileNode item;
  final Set<FileMenuAction> menuActions;

  /// `FileNode.apiPath` values with an extraction in flight.
  final Set<String> extractingPaths;
  final bool inArchive;
  final bool isSearchMode;

  /// Whether the viewer is an admin, who may move or delete the `users` and
  /// `groups` folders, a home folder (`users/<name>`) and a group's folder
  /// (`groups/<name>`) on the internal drive; a member may not (#2016).
  final bool isAdmin;
  final FileMenuActionDispatch onDispatchMenuAction;
  final void Function(FileNode)? onNavigateToFolder;

  @override
  Widget build(BuildContext context) {
    final extracting = extractingPaths.contains(item.apiPath);
    final serial = item.deviceSerial;
    final path = item.apiPath;
    final isStructuralDir =
        isUsersDir(serial, path) || isGroupsDir(serial, path);
    final canChange =
        !inArchive &&
        (isAdmin ||
            !(isStructuralDir ||
                isHomeRoot(serial, path) ||
                isGroupRoot(serial, path)));

    PopupMenuItem<FileMenuAction> entry(
      FileMenuAction action,
      Widget child, {
      bool enabled = true,
    }) => PopupMenuItem<FileMenuAction>(
      value: action,
      enabled: enabled,
      onTap: () => onDispatchMenuAction(context, item, action),
      child: child,
    );

    return PopupMenuButton<FileMenuAction>(
      icon: const Icon(QuarkIcons.more_vert),
      itemBuilder: (context) => [
        if (menuActions.contains(FileMenuAction.download))
          entry(FileMenuAction.download, const Text('Download')),
        if (menuActions.contains(FileMenuAction.moveRename) && canChange)
          entry(FileMenuAction.moveRename, const Text('Move/Rename')),
        if (menuActions.contains(FileMenuAction.share) &&
            !inArchive &&
            !isStructuralDir)
          entry(FileMenuAction.share, const Text('Share…')),
        if (menuActions.contains(FileMenuAction.delete) && canChange)
          entry(FileMenuAction.delete, const Text('Delete')),
        if (menuActions.contains(FileMenuAction.extractHere) &&
            !inArchive &&
            isArchiveNode(item))
          entry(
            FileMenuAction.extractHere,
            enabled: !extracting,
            extracting
                ? const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Extracting...'),
                    ],
                  )
                : const Text('Extract here'),
          ),
        if (menuActions.contains(FileMenuAction.navigateToFolder) &&
            isSearchMode &&
            onNavigateToFolder != null)
          PopupMenuItem<FileMenuAction>(
            value: FileMenuAction.navigateToFolder,
            onTap: () => onNavigateToFolder!(item),
            child: const Text('Navigate to folder'),
          ),
        if (menuActions.contains(FileMenuAction.restore))
          entry(FileMenuAction.restore, const Text('Restore')),
        if (menuActions.contains(FileMenuAction.deletePermanently))
          entry(
            FileMenuAction.deletePermanently,
            const Text('Delete permanently'),
          ),
      ],
    );
  }
}
