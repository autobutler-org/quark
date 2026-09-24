import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';

/// Runs one of the row's menu entries. The [BuildContext] is the one the menu
/// was built from — the three-dot button's or the row's, never the popup
/// route's, which is disposed as the menu closes — because the caller checks
/// it for mounting before it touches the tree.
typedef FileMenuActionDispatch =
    void Function(BuildContext context, FileNode item, FileMenuAction action);

/// What one file or folder's menu offers, built once and shown by both the
/// three-dot `FileMenuButton` and a long press on the row (#2245).
///
/// [entries] leaves out whatever does not apply to [item]: nothing that
/// changes or shares a file inside an archive, Extract only on an archive,
/// Convert video only on a video file, Navigate to folder only in search
/// results, and no Move/Rename or Delete on the `users` or `groups` folder, a
/// home folder, or a group's folder itself unless the viewer is an admin. Share is hidden on the `users` and `groups`
/// folders for everyone, admins included: access is additive down the tree, so
/// a grant there would expose every home or every group folder at once, and
/// the Quark refuses it (#2016).
@immutable
class FileMenu {
  const FileMenu({
    required this.item,
    required this.menuActions,
    required this.extractingPaths,
    required this.inArchive,
    required this.isSearchMode,
    required this.onDispatchMenuAction,
    this.isAdmin = false,
    this.onNavigateToFolder,
  });

  final FileNode item;

  /// The entries the menu may offer; one that does not apply to [item] is
  /// still left out.
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

  /// The entries for [item], empty when nothing applies to it.
  ///
  /// [dispatchContext] is handed to [onDispatchMenuAction] and has to outlive
  /// the menu, so it is the button's or the row's context rather than the one
  /// an entry is built with.
  List<PopupMenuEntry<FileMenuAction>> entries(BuildContext dispatchContext) {
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
      onTap: () => onDispatchMenuAction(dispatchContext, item, action),
      child: child,
    );

    return [
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
                    QuarkLoader(size: 16),
                    SizedBox(width: 8),
                    Text('Extracting...'),
                  ],
                )
              : const Text('Extract here'),
        ),
      if (menuActions.contains(FileMenuAction.convertVideo) &&
          !inArchive &&
          !item.isDir &&
          fileKindForName(item.name) == FileKind.video)
        entry(FileMenuAction.convertVideo, const Text('Convert video')),
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
    ];
  }

  /// Opens the menu where the finger or pointer is, [globalPosition].
  ///
  /// Does nothing when no entry applies to [item] — an empty menu is a box
  /// with nothing to pick out of it. [context] is what the entries dispatch
  /// against, so it must still be mounted once the menu has closed.
  Future<void> showAt(BuildContext context, Offset globalPosition) async {
    final items = entries(context);
    if (items.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    await showMenu<FileMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }
}
