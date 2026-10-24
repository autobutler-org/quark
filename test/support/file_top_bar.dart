import 'package:flutter/material.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';

/// A [FileTopBar] on `/docs` at the root, idle, with every callback it
/// requires a no-op, so a test passes only the part it is about.
///
/// The optional callbacks stay null unless a test passes them, as they do in
/// [FileTopBar] itself.
FileTopBar testFileTopBar({
  String currentPath = '/docs',
  bool isGridView = false,
  bool isUnifiedView = false,
  bool isSearchMode = false,
  bool isUploading = false,
  int uploadTotal = 0,
  int uploadCompleted = 0,
  ValueChanged<String>? onPathSelected,
  ValueChanged<String>? onSearchChanged,
  ValueChanged<String>? onSearchDraft,
  VoidCallback? onSearchClosed,
  VoidCallback? onUploadPressed,
  VoidCallback? onUploadPhotosPressed,
  VoidCallback? onUploadFolderPressed,
  VoidCallback? onCancelUploadPressed,
  VoidCallback? onStartSelection,
  Set<FileListColumn> columns = const {},
  FileListColumnToggle? onColumnToggled,
}) => FileTopBar(
  currentPath: currentPath,
  rootPath: '',
  isGridView: isGridView,
  isUnifiedView: isUnifiedView,
  onToggleUnifiedView: () {},
  isSearchMode: isSearchMode,
  isUploading: isUploading,
  isCreatingFolder: false,
  uploadTotal: uploadTotal,
  uploadCompleted: uploadCompleted,
  isRefreshing: false,
  onGoHome: () {},
  onGoUp: () {},
  onPathSelected: onPathSelected,
  onToggleView: () {},
  onSearchChanged: onSearchChanged ?? (_) {},
  onSearchDraft: onSearchDraft,
  onSearchClosed: onSearchClosed ?? () {},
  onRefresh: () {},
  onUploadPressed: onUploadPressed ?? () {},
  onUploadPhotosPressed: onUploadPhotosPressed,
  onUploadFolderPressed: onUploadFolderPressed,
  onCancelUploadPressed: onCancelUploadPressed,
  onCreateFolderPressed: () {},
  onNewFilePressed: () {},
  onStartSelection: onStartSelection,
  columns: columns,
  onColumnToggled: onColumnToggled,
);
