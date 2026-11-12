import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/file_browser/file_browser_view/folder_drop_target.dart';

/// Wraps a row in a [FolderDropTarget] when the row is a folder and this
/// platform can take a drop at all; every other row passes straight through.
class FolderDropWrapper extends StatelessWidget {
  const FolderDropWrapper({
    required this.item,
    required this.currentPath,
    required this.onDropToFolder,
    this.onFolderDragEnter,
    this.onFolderDragExit,
    required this.child,
    super.key,
  });

  final FileNode item;
  final String currentPath;
  final Future<void> Function(List<DropItem> droppedItems, String targetPath)?
  onDropToFolder;
  final VoidCallback? onFolderDragEnter;
  final VoidCallback? onFolderDragExit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onDrop = onDropToFolder;
    if (!kIsWeb || onDrop == null || !item.isDir) {
      return child;
    }
    return FolderDropTarget(
      targetPath: normalizePath(joinPath(currentPath, item.name)),
      onDropToFolder: onDrop,
      onFolderDragEnter: onFolderDragEnter,
      onFolderDragExit: onFolderDragExit,
      child: child,
    );
  }
}
