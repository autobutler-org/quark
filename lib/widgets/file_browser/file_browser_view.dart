import 'package:quark/models/file_node.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_sort_header.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header.dart';
import 'package:quark/widgets/file_browser/file_browser_view/folder_drop_wrapper.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

enum FileMenuAction {
  download,
  moveRename,
  delete,
  navigateToFolder,
  extractHere,

  /// Puts a trashed item back where it was deleted from.
  restore,

  /// Deletes a trashed item for good.
  deletePermanently,
}

enum SortColumn { name, type, size, device }

enum SortDirection { asc, desc }

class FileBrowserView extends StatefulWidget {
  const FileBrowserView({
    required this.filesFuture,
    required this.onFileMenuAction,
    required this.onOpenDirectory,
    required this.isGridView,
    this.menuActions = defaultMenuActions,
    this.subtitleFor,
    this.emptyBuilder,
    required this.currentPath,
    this.initialData,
    this.isUnifiedView = true,
    this.onDropToFolder,
    this.onFolderDragEnter,
    this.onFolderDragExit,
    this.scrollController,
    this.showFileSizeAndMenu = true,
    this.isSearchMode = false,
    this.onNavigateToFolder,
    this.inArchive = false,
    this.isInitialLoad = false,
    this.errorBuilder,
    this.loadingBuilder,
    this.selectionMode = false,
    this.selectedPaths = const {},
    this.onSelectionChanged,
    super.key,
  });

  final Future<List<FileNode>> filesFuture;
  final List<FileNode>? initialData;

  /// What the Files page offers on a file or folder.
  static const Set<FileMenuAction> defaultMenuActions = {
    FileMenuAction.download,
    FileMenuAction.moveRename,
    FileMenuAction.delete,
    FileMenuAction.extractHere,
    FileMenuAction.navigateToFolder,
  };

  final Future<void> Function(FileNode, FileMenuAction) onFileMenuAction;

  /// Opens a file or folder. Null leaves rows inert outside selection mode —
  /// the trash lists items it will not open.
  final void Function(FileNode)? onOpenDirectory;
  final bool isGridView;

  /// The entries each item's menu may offer; an entry that does not apply to
  /// an item (Extract on a non-archive) is still left out.
  final Set<FileMenuAction> menuActions;

  /// A second line under each list row, or null for none. The grid has no
  /// room for one and ignores it.
  final String? Function(FileNode node)? subtitleFor;

  /// Replaces the "No files yet" state for an empty listing.
  final WidgetBuilder? emptyBuilder;

  /// When true (default), files from all devices are shown merged.
  /// When false, files are grouped by device with a section header per device.
  final bool isUnifiedView;
  final String currentPath;
  final Future<void> Function(List<DropItem> droppedItems, String targetPath)?
  onDropToFolder;
  final VoidCallback? onFolderDragEnter;
  final VoidCallback? onFolderDragExit;
  final ScrollController? scrollController;
  final bool showFileSizeAndMenu;
  final bool isSearchMode;
  final void Function(FileNode)? onNavigateToFolder;

  /// When true, we are browsing inside an archive — only download is available
  /// for files (no move/rename/delete).
  final bool inArchive;

  /// When true, show a spinner unconditionally — used during the initial page
  /// load before any data has been fetched. Without this, the pre-resolved
  /// empty default future would immediately show "No files yet" instead of
  /// a spinner.
  final bool isInitialLoad;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final WidgetBuilder? loadingBuilder;

  /// When true, items show checkboxes and taps toggle selection instead of
  /// opening the file/folder.
  final bool selectionMode;

  /// The set of `FileNode.apiPath` values currently selected. The parent
  /// widget owns this state; [FileBrowserView] reflects it.
  final Set<String> selectedPaths;

  /// Called when the user taps an item in selection mode or long-presses to
  /// enter selection mode. The argument is the tapped [FileNode].
  /// The parent widget should toggle the path in its own set and rebuild.
  final void Function(FileNode node, {required bool enterSelectionMode})?
  onSelectionChanged;

  @override
  State<FileBrowserView> createState() => _FileBrowserViewState();
}

class _FileBrowserViewState extends State<FileBrowserView> {
  SortColumn _sortColumn = SortColumn.name;
  SortDirection _sortDirection = SortDirection.asc;
  final Set<String> _extractingPaths = {};

  void _toggleSort(SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDirection = _sortDirection == SortDirection.asc
            ? SortDirection.desc
            : SortDirection.asc;
      } else {
        _sortColumn = column;
        _sortDirection = SortDirection.asc;
      }
    });
  }

  List<FileNode> _sorted(List<FileNode> files) {
    final sorted = List<FileNode>.from(files);
    sorted.sort((a, b) {
      // Directories always first.
      final dirCmp = (b.isDir ? 1 : 0) - (a.isDir ? 1 : 0);
      if (dirCmp != 0) return dirCmp;

      int cmp;
      switch (_sortColumn) {
        case SortColumn.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortColumn.type:
          cmp = _fileType(a).compareTo(_fileType(b));
        case SortColumn.size:
          cmp = a.size.compareTo(b.size);
        case SortColumn.device:
          cmp = a.deviceName.toLowerCase().compareTo(
            b.deviceName.toLowerCase(),
          );
      }
      return _sortDirection == SortDirection.asc ? cmp : -cmp;
    });
    return sorted;
  }

  void _dispatchMenuAction(
    BuildContext context,
    FileNode item,
    FileMenuAction action,
  ) {
    Future<void>.delayed(Duration.zero, () async {
      if (!context.mounted) return;
      if (action == FileMenuAction.extractHere) {
        if (_extractingPaths.contains(item.apiPath)) return;
        if (mounted) setState(() => _extractingPaths.add(item.apiPath));
        try {
          await widget.onFileMenuAction(item, action);
        } finally {
          if (mounted) setState(() => _extractingPaths.remove(item.apiPath));
        }
      } else {
        await widget.onFileMenuAction(item, action);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<List<FileNode>>(
      future: widget.filesFuture,
      initialData: widget.initialData,
      builder: (context, snapshot) {
        if (widget.isInitialLoad ||
            (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)) {
          if (widget.loadingBuilder != null) {
            return widget.loadingBuilder!(context);
          }
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final error = snapshot.error!;
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, error);
          }
          return Center(
            child: Text(
              Errors.message(error, 'load your files'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        final raw = snapshot.data ?? const <FileNode>[];
        if (raw.isEmpty) {
          if (widget.emptyBuilder != null) {
            return widget.emptyBuilder!(context);
          }
          return const EmptyStateWidget(
            icon: QuarkIcons.folder_open_outlined,
            headline: 'No files yet',
            subtext:
                'Upload files using the button above, or drag and drop here.',
          );
        }

        final files = _sorted(raw);

        // ── Segmented view ────────────────────────────────────────────────
        if (!widget.isUnifiedView && !widget.isSearchMode) {
          final groups = <String, List<FileNode>>{};
          for (final f in files) {
            final key = f.deviceName.isNotEmpty
                ? f.deviceName
                : 'Unknown Device';
            groups.putIfAbsent(key, () => []).add(f);
          }
          return Column(
            children: [
              FileSortHeader(
                sortColumn: _sortColumn,
                sortDirection: _sortDirection,
                onToggleSort: _toggleSort,
                showFileSizeAndMenu: widget.showFileSizeAndMenu,
              ),
              Expanded(
                child: ListView(
                  controller: widget.scrollController,
                  children: [
                    for (final entry in groups.entries)
                      ExpansionTile(
                        initiallyExpanded: true,
                        leading: const Icon(QuarkIcons.storage_rounded),
                        title: Text(entry.key),
                        subtitle: Text(
                          '${entry.value.length} '
                          'item${entry.value.length == 1 ? '' : 's'}',
                        ),
                        children: [
                          for (final item in entry.value)
                            FolderDropWrapper(
                              item: item,
                              currentPath: widget.currentPath,
                              onDropToFolder: widget.onDropToFolder,
                              onFolderDragEnter: widget.onFolderDragEnter,
                              onFolderDragExit: widget.onFolderDragExit,
                              child: FileBrowserListTile(
                                item: item,
                                isSelected: widget.selectedPaths.contains(
                                  item.apiPath,
                                ),
                                extractingPaths: _extractingPaths,
                                showFileSizeAndMenu: widget.showFileSizeAndMenu,
                                inArchive: widget.inArchive,
                                isSearchMode: widget.isSearchMode,
                                selectionMode: widget.selectionMode,
                                onDispatchMenuAction: _dispatchMenuAction,
                                onOpenDirectory: widget.onOpenDirectory,
                                menuActions: widget.menuActions,
                                subtitle: widget.subtitleFor?.call(item),
                                onNavigateToFolder: widget.onNavigateToFolder,
                                onSelectionChanged: widget.onSelectionChanged,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        // ── Grid view ─────────────────────────────────────────────────────
        if (widget.isGridView) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          const horizontalPadding = 16.0;
          const crossAxisSpacing = 8.0;
          const minTileWidth = 180.0;
          final usableWidth = screenWidth - horizontalPadding;
          final calculatedCount =
              ((usableWidth + crossAxisSpacing) /
                      (minTileWidth + crossAxisSpacing))
                  .floor();
          final crossAxisCount = calculatedCount < 1 ? 1 : calculatedCount;

          return Column(
            children: [
              FileGridSortHeader(
                sortColumn: _sortColumn,
                sortDirection: _sortDirection,
                onToggleSort: _toggleSort,
              ),
              Expanded(
                child: GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: files.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final item = files[index];
                    final isSelected = widget.selectedPaths.contains(
                      item.apiPath,
                    );
                    return FolderDropWrapper(
                      item: item,
                      currentPath: widget.currentPath,
                      onDropToFolder: widget.onDropToFolder,
                      onFolderDragEnter: widget.onFolderDragEnter,
                      onFolderDragExit: widget.onFolderDragExit,
                      child: Card(
                        clipBehavior: Clip.hardEdge,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.55)
                            : null,
                        child: InkWell(
                          onTap: widget.selectionMode
                              ? () => widget.onSelectionChanged?.call(
                                  item,
                                  enterSelectionMode: false,
                                )
                              : widget.onOpenDirectory == null
                              ? null
                              : () => widget.onOpenDirectory!(item),
                          onLongPress: widget.inArchive || widget.selectionMode
                              ? null
                              : () => widget.onSelectionChanged?.call(
                                  item,
                                  enterSelectionMode: true,
                                ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: FileGridPreview(item: item),
                                    ),
                                    const SizedBox(height: 8),
                                    Flexible(
                                      child: Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (widget.showFileSizeAndMenu)
                                          Flexible(
                                            child: Text(
                                              formatFileSize(
                                                item.size,
                                                item.isDir,
                                                compressedSize:
                                                    item.compressedSize,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        if (widget.showFileSizeAndMenu)
                                          FileMenuButton(
                                            item: item,
                                            menuActions: widget.menuActions,
                                            extractingPaths: _extractingPaths,
                                            inArchive: widget.inArchive,
                                            isSearchMode: widget.isSearchMode,
                                            onDispatchMenuAction:
                                                _dispatchMenuAction,
                                            onNavigateToFolder:
                                                widget.onNavigateToFolder,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Checkbox overlay in selection mode.
                              if (widget.selectionMode)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withValues(alpha: 0.75),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 20,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        // ── List view ─────────────────────────────────────────────────────
        return Column(
          children: [
            FileSortHeader(
              sortColumn: _sortColumn,
              sortDirection: _sortDirection,
              onToggleSort: _toggleSort,
              showFileSizeAndMenu: widget.showFileSizeAndMenu,
            ),
            Expanded(
              child: ListView.separated(
                controller: widget.scrollController,
                itemCount: files.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final item = files[index];
                  return FolderDropWrapper(
                    item: item,
                    currentPath: widget.currentPath,
                    onDropToFolder: widget.onDropToFolder,
                    onFolderDragEnter: widget.onFolderDragEnter,
                    onFolderDragExit: widget.onFolderDragExit,
                    child: FileBrowserListTile(
                      item: item,
                      isSelected: widget.selectedPaths.contains(item.apiPath),
                      extractingPaths: _extractingPaths,
                      showFileSizeAndMenu: widget.showFileSizeAndMenu,
                      inArchive: widget.inArchive,
                      isSearchMode: widget.isSearchMode,
                      selectionMode: widget.selectionMode,
                      onDispatchMenuAction: _dispatchMenuAction,
                      onOpenDirectory: widget.onOpenDirectory,
                      menuActions: widget.menuActions,
                      subtitle: widget.subtitleFor?.call(item),
                      onNavigateToFolder: widget.onNavigateToFolder,
                      onSelectionChanged: widget.onSelectionChanged,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fileType(FileNode node) {
    if (node.isDir) return '';
    final dot = node.name.lastIndexOf('.');
    if (dot < 0) return 'file';
    return node.name.substring(dot + 1).toLowerCase();
  }
}
