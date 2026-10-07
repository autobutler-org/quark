import 'package:flutter/material.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';

/// One file or folder in the list view: its name, then one cell per entry of
/// [columns], laid out with the flexes `FileSortHeader` uses.
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
    required this.columns,
    this.menuActions = FileBrowserView.defaultMenuActions,
    this.isAdmin = false,
    this.subtitle,
    this.onNavigateToFolder,
    this.onSelectionChanged,
    super.key,
  });

  final FileNode item;
  final bool isSelected;

  /// Passed to [FileMenu.isAdmin].
  final bool isAdmin;

  /// `FileNode.apiPath` values with an extraction in flight; the owner mutates
  /// this set and rebuilds, so it is read rather than copied.
  final Set<String> extractingPaths;
  final bool showFileSizeAndMenu;

  /// The columns after the name, in the order they are shown.
  final List<FileListColumn> columns;
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
  final void Function(FileNode node)? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final menu = FileMenu(
      item: item,
      menuActions: menuActions,
      extractingPaths: extractingPaths,
      inArchive: inArchive,
      isSearchMode: isSearchMode,
      isAdmin: isAdmin,
      onDispatchMenuAction: onDispatchMenuAction,
      onNavigateToFolder: onNavigateToFolder,
    );
    // ListTile.onLongPress hands over no position, so the gestures are caught
    // outside it; the row's own context is what the entries dispatch against,
    // since it outlives the menu. A right-click opens the same menu (#2276).
    final hasMenu = showFileSizeAndMenu && !selectionMode;
    return GestureDetector(
      onLongPressStart: hasMenu
          ? (details) => menu.showAt(context, details.globalPosition)
          : null,
      onSecondaryTapUp: hasMenu
          ? (details) => menu.showAt(context, details.globalPosition)
          : null,
      child: Material(
        color: isSelected
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: selectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => onSelectionChanged?.call(item),
                )
              : FileListLeading(key: ValueKey(item.apiPath), item: item),
          title: Row(
            children: [
              Expanded(
                flex: FileListColumn.nameFlex,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final column in columns)
                Expanded(
                  flex: FileListColumn.flex,
                  child: Text(
                    fileListCellText(column, item),
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
          trailing: showFileSizeAndMenu ? FileMenuButton(menu: menu) : null,
          onTap: selectionMode
              ? () => onSelectionChanged?.call(item)
              : onOpenDirectory == null
              ? null
              : () => onOpenDirectory!(item),
        ),
      ),
    );
  }
}
