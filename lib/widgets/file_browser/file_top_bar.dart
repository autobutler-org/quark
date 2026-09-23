import 'dart:async';

import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_nav_buttons.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_path_row.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_search_area.dart';
import 'package:flutter/material.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Files page's top bar: the breadcrumb for the current folder, the way
/// up, and search, on the same [QuarkAppBar] every other page wears (#2311).
///
/// Search lives here rather than in the page because the inline field owns a
/// controller, a focus node and a debounce. The path row below is a
/// [FileTopBarPathRow], whose actions collapse into the bar's labeled menu on
/// a phone.
///
/// Probe keys: `file_top_bar_select`, plus those of [FileTopBarNavButtons],
/// [FileTopBarSearchArea] and [FileTopBarPathRow].
class FileTopBar extends StatefulWidget implements PreferredSizeWidget {
  const FileTopBar({
    required this.currentPath,
    required this.rootPath,
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
    this.onSearchDraft,
    required this.onSearchClosed,
    required this.onRefresh,
    required this.onUploadPressed,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    required this.onCreateFolderPressed,
    required this.onNewFilePressed,
    this.onStartSelection,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    super.key,
  });

  /// Enters multi-select, for a pointer that cannot long-press (#2057).
  /// Null hides the control.
  final VoidCallback? onStartSelection;

  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root. Up and
  /// the breadcrumb both stop here (#2139).
  final String rootPath;
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

  /// The trimmed field text, including `''` when the field is cleared.
  ///
  /// Called synchronously on every change, before the debounced
  /// [onSearchChanged], so a banner can follow what is being typed instead of
  /// the search that has not started yet.
  final ValueChanged<String>? onSearchDraft;

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
  final List<StorageDevice>? devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  /// One bar row, plus the path row outside search.
  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (isSearchMode ? 0 : QuarkAppBarBottom.height),
  );

  @override
  State<FileTopBar> createState() => _FileTopBarState();
}

class _FileTopBarState extends State<FileTopBar> {
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
    widget.onSearchDraft?.call('');
    widget.onSearchClosed();
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    // Before the debounce, including when the field is cleared, so the banner
    // can follow the field instead of the previous search.
    widget.onSearchDraft?.call(trimmed);
    _searchDebounce?.cancel();
    if (trimmed.isEmpty) {
      // Empty query — close search immediately.
      widget.onSearchClosed();
      return;
    }
    // Debounce 350 ms so we don't fire on every keystroke.
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      widget.onSearchChanged(trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onStartSelection = widget.onStartSelection;
    return QuarkAppBar(
      label: 'Files',
      icon: QuarkIcons.storage_rounded,
      onRefresh: widget.onRefresh,
      isRefreshing: widget.isRefreshing,
      middle: Row(
        spacing: QuarkTokens.of(context).spacingXs,
        children: [
          FileTopBarNavButtons(
            navEnabled: !widget.disableNavigation,
            currentPath: widget.currentPath,
            rootPath: widget.rootPath,
            onGoUp: widget.onGoUp,
          ),
          // Holds the search field when it is open and pins the search button
          // to the trailing edge when it is not.
          Expanded(
            child: FileTopBarSearchArea(
              expanded: _searchExpanded,
              controller: _searchController,
              focusNode: _searchFocusNode,
              onOpen: _openSearch,
              onChanged: _onSearchChanged,
              onClose: _closeSearch,
            ),
          ),
        ],
      ),
      actions: [
        // Selecting used to be a long press on a row, a gesture a mouse does
        // not make, so on the web the whole feature was invisible (#2057).
        // This button is the only way in now that a long press opens the
        // row's menu instead (#2245).
        if (onStartSelection != null)
          QuarkBarIconButton(
            key: const ValueKey('file_top_bar_select'),
            icon: QuarkIcons.check_circle_outline,
            tooltip: 'Select',
            onPressed: onStartSelection,
          ),
        const AppThemeToggle(),
      ],
      bottom: widget.isSearchMode
          ? null
          : FileTopBarPathRow(
              currentPath: widget.currentPath,
              rootPath: widget.rootPath,
              navEnabled: !widget.disableNavigation,
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
    );
  }
}
