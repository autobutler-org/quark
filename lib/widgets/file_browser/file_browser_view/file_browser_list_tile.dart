import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_device_tags.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark_widgets/quark_widgets.dart' show FileNameText;

/// One file or folder in the list view: its name, then one cell per entry of
/// [columns], laid out with the flexes `FileSortHeader` uses.
///
/// [compact], on a phone, drops the columns for one line of name over one
/// muted line of when and how big ([fileRowMetaText]), in a row at least
/// [compactMinHeight] tall (#4226).
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
    this.onVersionHistory,
    this.onSelectionChanged,
    this.compact = false,
    super.key,
  });

  /// The least a compact row is tall.
  static const double compactMinHeight = 56;

  /// Whether this is the phone's one-line row rather than the columned one.
  /// [columns] is ignored when true.
  final bool compact;

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

  /// Passed to [FileMenu.onVersionHistory].
  final void Function(FileNode)? onVersionHistory;
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
      onVersionHistory: onVersionHistory,
    );
    // ListTile.onLongPress hands over no position, so the gestures are caught
    // outside it; the row's own context is what the entries dispatch against,
    // since it outlives the menu. A right-click opens the same menu (#2276).
    final hasMenu = showFileSizeAndMenu && !selectionMode;
    // A compact row's second line says when and how big; a caller's own
    // line, such as where a trashed item came from, follows it.
    final subtitleText = compact
        ? [fileRowMetaText(item, DateTime.now()), ?subtitle].join(' · ')
        : subtitle;
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
              : FileListLeading(key: fileThumbnailKey(item), item: item),
          title: compact
              ? FileNameText(item.name)
              : Row(
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
                        // The device column is a tag per device, in its color.
                        child: column == FileListColumn.device
                            ? Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: FileDeviceTags(item: item),
                              )
                            : Text(
                                fileListCellText(column, item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                      ),
                  ],
                ),
          subtitle: subtitleText == null
              ? null
              : Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
          minTileHeight: compact ? compactMinHeight : null,
          // The menu button is a 48dp target at every width.
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
