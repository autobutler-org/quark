import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';

/// One file or folder in the list view.
class FileBrowserListTile extends StatelessWidget {
  const FileBrowserListTile({
    required this.item,
    required this.isSelected,
    required this.extractingPaths,
    required this.showFileSizeAndMenu,
    required this.inArchive,
    required this.isSearchMode,
    required this.selectionMode,
    required this.onDispatchMenuAction,
    required this.onOpenDirectory,
    this.menuActions = FileBrowserView.defaultMenuActions,
    this.subtitle,
    this.onNavigateToFolder,
    this.onSelectionChanged,
    super.key,
  });

  final FileNode item;
  final bool isSelected;

  /// `FileNode.apiPath` values with an extraction in flight; the owner mutates
  /// this set and rebuilds, so it is read rather than copied.
  final Set<String> extractingPaths;
  final bool showFileSizeAndMenu;
  final bool inArchive;
  final bool isSearchMode;
  final bool selectionMode;
  final FileMenuActionDispatch onDispatchMenuAction;

  /// Opens the row. Null leaves rows inert outside selection mode.
  final void Function(FileNode)? onOpenDirectory;

  /// The entries the row's menu offers.
  final Set<FileMenuAction> menuActions;

  /// A second line under the row, or null for none.
  final String? subtitle;
  final void Function(FileNode)? onNavigateToFolder;
  final void Function(FileNode node, {required bool enterSelectionMode})?
  onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? colors.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: selectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) =>
                    onSelectionChanged?.call(item, enterSelectionMode: false),
              )
            : FileListLeading(item: item),
        title: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            if (showFileSizeAndMenu)
              Expanded(
                flex: 2,
                child: Text(
                  formatFileSize(
                    item.size,
                    item.isDir,
                    compressedSize: item.compressedSize,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
        trailing: showFileSizeAndMenu
            ? FileMenuButton(
                item: item,
                menuActions: menuActions,
                extractingPaths: extractingPaths,
                inArchive: inArchive,
                isSearchMode: isSearchMode,
                onDispatchMenuAction: onDispatchMenuAction,
                onNavigateToFolder: onNavigateToFolder,
              )
            : null,
        onTap: selectionMode
            ? () => onSelectionChanged?.call(item, enterSelectionMode: false)
            : onOpenDirectory == null
            ? null
            : () => onOpenDirectory!(item),
        onLongPress: inArchive || selectionMode
            ? null
            : () => onSelectionChanged?.call(item, enterSelectionMode: true),
      ),
    );
  }
}
