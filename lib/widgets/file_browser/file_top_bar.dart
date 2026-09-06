import 'dart:async';

import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_path_row.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_row.dart';
import 'package:flutter/material.dart';

class FileTopBar extends StatefulWidget {
  const FileTopBar({
    required this.currentPath,
    required this.isGridView,
    required this.isUnifiedView,
    required this.onToggleUnifiedView,
    required this.isSearchMode,
    required this.isUploading,
    required this.isCreatingFolder,
    this.disableNavigation = false,
    this.uploadTotal = 0,
    this.uploadCompleted = 0,
    required this.isRefreshing,
    required this.onGoHome,
    required this.onGoUp,
    this.onPathSelected,
    required this.onToggleView,
    required this.onSearchChanged,
    required this.onSearchClosed,
    required this.onRefresh,
    required this.onUploadPressed,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    required this.onCreateFolderPressed,
    required this.onNewFilePressed,
    required this.onOpenDrawer,
    required this.onOpenSettings,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    super.key,
  });

  final String currentPath;
  final bool isGridView;
  final bool isUnifiedView;
  final VoidCallback onToggleUnifiedView;
  final bool isSearchMode;
  final bool isUploading;
  final bool isCreatingFolder;
  final bool disableNavigation;
  final int uploadTotal;
  final int uploadCompleted;
  final bool isRefreshing;
  final VoidCallback onGoHome;
  final VoidCallback onGoUp;
  final ValueChanged<String>? onPathSelected;
  final VoidCallback onToggleView;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClosed;
  final VoidCallback onRefresh;
  final VoidCallback onUploadPressed;

  /// Photos library upload, when Files cannot see the Camera Roll.
  ///
  /// iOS only. Null everywhere else, where the ordinary file picker already
  /// includes photos. When set, Upload opens a chooser with Photos first.
  final VoidCallback? onUploadPhotosPressed;

  /// Folder upload, when the platform has a folder picker at all.
  ///
  /// It gets no button of its own: to the user "upload" is one action, and
  /// whether they are uploading a file or a folder is a property of what they
  /// pick, not a different feature. Null on mobile, which has no folder
  /// picker — there Upload goes straight to the file picker unless Photos
  /// is also offered.
  final VoidCallback? onUploadFolderPressed;

  /// Abandons an upload in progress.
  ///
  /// The chip stays live while uploading so this is reachable: a batch that is
  /// failing its way through a thousand files should not leave the user
  /// watching a disabled button.
  final VoidCallback? onCancelUploadPressed;
  final VoidCallback onCreateFolderPressed;
  final VoidCallback onNewFilePressed;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenSettings;
  final List<StorageDevice>? devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  @override
  State<FileTopBar> createState() => _FileTopBarState();
}

class _FileTopBarState extends State<FileTopBar> {
  final _viewsMenuController = MenuController();
  final _hiddenCrumbsController = MenuController();

  // ── Inline search ─────────────────────────────────────────────────────────
  bool _searchExpanded = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  @override
  void didUpdateWidget(FileTopBar old) {
    super.didUpdateWidget(old);
    // If the parent closed search externally (e.g. navigating to a folder),
    // collapse the inline field and clear it.
    if (!widget.isSearchMode && old.isSearchMode && _searchExpanded) {
      setState(() => _searchExpanded = false);
      _searchController.clear();
      _searchDebounce?.cancel();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchExpanded = true);
    // Focus after the frame so AnimatedSize has time to expand first.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  void _closeSearch() {
    setState(() => _searchExpanded = false);
    _searchController.clear();
    _searchDebounce?.cancel();
    widget.onSearchClosed();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      // Empty query — close search immediately.
      widget.onSearchClosed();
      return;
    }
    // Debounce 350 ms so we don't fire on every keystroke.
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      widget.onSearchChanged(query.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        border: Border(bottom: BorderSide(color: colorScheme.outline)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileTopBarRow(
              currentPath: widget.currentPath,
              navEnabled: !widget.disableNavigation,
              isRefreshing: widget.isRefreshing,
              searchExpanded: _searchExpanded,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              onGoUp: widget.onGoUp,
              onRefresh: widget.onRefresh,
              onOpenSearch: _openSearch,
              onSearchChanged: _onSearchChanged,
              onCloseSearch: _closeSearch,
              onOpenDrawer: widget.onOpenDrawer,
              onOpenSettings: widget.onOpenSettings,
            ),
            if (!widget.isSearchMode)
              FileTopBarPathRow(
                currentPath: widget.currentPath,
                navEnabled: !widget.disableNavigation,
                viewsMenuController: _viewsMenuController,
                hiddenCrumbsController: _hiddenCrumbsController,
                isGridView: widget.isGridView,
                isUnifiedView: widget.isUnifiedView,
                isUploading: widget.isUploading,
                isCreatingFolder: widget.isCreatingFolder,
                uploadTotal: widget.uploadTotal,
                uploadCompleted: widget.uploadCompleted,
                onGoHome: widget.onGoHome,
                onToggleView: widget.onToggleView,
                onToggleUnifiedView: widget.onToggleUnifiedView,
                onUploadPressed: widget.onUploadPressed,
                onCreateFolderPressed: widget.onCreateFolderPressed,
                onNewFilePressed: widget.onNewFilePressed,
                onPathSelected: widget.onPathSelected,
                onUploadPhotosPressed: widget.onUploadPhotosPressed,
                onUploadFolderPressed: widget.onUploadFolderPressed,
                onCancelUploadPressed: widget.onCancelUploadPressed,
                devices: widget.devices,
                activeDevicePaths: widget.activeDevicePaths,
                onDeviceToggled: widget.onDeviceToggled,
              ),
          ],
        ),
      ),
    );
  }
}
