import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_actions.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_breadcrumb.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_device_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_views_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The lower half of the top bar: where the user is, and what they can do
/// here, as a [QuarkAppBarBottom].
///
/// On a wide bar the device filter, the create chips and the view toggles sit
/// beside the breadcrumb. Below the bar's breakpoint they give way to the
/// labeled Views menu, and creating moves to the floating button.
class FileTopBarPathRow extends StatelessWidget implements PreferredSizeWidget {
  const FileTopBarPathRow({
    required this.currentPath,
    required this.rootPath,
    required this.navEnabled,
    required this.hiddenCrumbsController,
    required this.isGridView,
    required this.isUnifiedView,
    required this.isUploading,
    required this.isCreatingFolder,
    required this.uploadTotal,
    required this.uploadCompleted,
    required this.onGoHome,
    required this.onToggleView,
    required this.onToggleUnifiedView,
    required this.onUploadPressed,
    required this.onCreateFolderPressed,
    required this.onNewFilePressed,
    this.onPathSelected,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    super.key,
  });

  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root.
  final String rootPath;
  final bool navEnabled;
  final MenuController hiddenCrumbsController;
  final bool isGridView;
  final bool isUnifiedView;
  final bool isUploading;
  final bool isCreatingFolder;
  final int uploadTotal;
  final int uploadCompleted;
  final VoidCallback onGoHome;
  final VoidCallback onToggleView;
  final VoidCallback onToggleUnifiedView;
  final VoidCallback onUploadPressed;
  final VoidCallback onCreateFolderPressed;
  final VoidCallback onNewFilePressed;
  final ValueChanged<String>? onPathSelected;
  final VoidCallback? onUploadPhotosPressed;
  final VoidCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;
  final List<StorageDevice>? devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final breadcrumb = FileTopBarBreadcrumb(
      currentPath: currentPath,
      rootPath: rootPath,
      navEnabled: navEnabled,
      hiddenCrumbsController: hiddenCrumbsController,
      onGoHome: onGoHome,
      onPathSelected: onPathSelected,
    );
    final devices = this.devices;
    return QuarkAppBarBottom(
      // At the root the breadcrumb is only the home icon: let the pill shrink
      // to it rather than stretch across the row.
      lead: currentPath.isEmpty
          ? Align(alignment: Alignment.centerLeft, child: breadcrumb)
          : breadcrumb,
      actions: [
        if (devices != null && devices.length > 1)
          FileTopBarDeviceChips(
            devices: devices,
            activeDevicePaths: activeDevicePaths,
            onDeviceToggled: onDeviceToggled,
          ),
        FileTopBarActions(
          isUploading: isUploading,
          uploadTotal: uploadTotal,
          uploadCompleted: uploadCompleted,
          isCreatingFolder: isCreatingFolder,
          onUploadPressed: onUploadPressed,
          onCreateFolderPressed: onCreateFolderPressed,
          onNewFilePressed: onNewFilePressed,
          onUploadPhotosPressed: onUploadPhotosPressed,
          onUploadFolderPressed: onUploadFolderPressed,
          onCancelUploadPressed: onCancelUploadPressed,
        ),
        FileTopBarViewChips(
          isGridView: isGridView,
          isUnifiedView: isUnifiedView,
          onToggleView: onToggleView,
          onToggleUnifiedView: onToggleUnifiedView,
        ),
      ],
      menuChildren: [
        FileTopBarViewsMenu(
          isGridView: isGridView,
          isUnifiedView: isUnifiedView,
          onToggleView: onToggleView,
          onToggleUnifiedView: onToggleUnifiedView,
          devices: devices,
          activeDevicePaths: activeDevicePaths,
          onDeviceToggled: onDeviceToggled,
        ),
      ],
    );
  }
}
