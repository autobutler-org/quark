import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_actions.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_breadcrumb.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_device_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_views_menu.dart';

/// The lower half of the top bar: where the user is, and what they can do
/// here. Under 860 px everything but the breadcrumb collapses into the Views
/// menu, which is the only place the two layouts differ.
class FileTopBarPathRow extends StatelessWidget {
  const FileTopBarPathRow({
    required this.currentPath,
    required this.navEnabled,
    required this.viewsMenuController,
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
  final bool navEnabled;
  final MenuController viewsMenuController;
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outline, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;

          // When at root the breadcrumb contains only the home icon.
          // Wrap it in Expanded only when there are path segments so that
          // the LayoutBuilder inside gets a bounded width for truncation.
          // At root we use Spacer() instead, letting the pill shrink to its
          // content and leaving the middle of the row open.
          final atRoot = currentPath.isEmpty;

          final breadcrumb = FileTopBarBreadcrumb(
            currentPath: currentPath,
            navEnabled: navEnabled,
            hiddenCrumbsController: hiddenCrumbsController,
            onGoHome: onGoHome,
            onPathSelected: onPathSelected,
          );

          if (isCompact) {
            return Row(
              children: [
                if (atRoot) ...[
                  breadcrumb,
                  const Spacer(),
                ] else
                  Expanded(child: breadcrumb),
                const SizedBox(width: 8),
                FileTopBarViewsMenu(
                  controller: viewsMenuController,
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

          // Desktop: breadcrumb + optional device chips + create actions + view chips.
          return Row(
            children: [
              if (atRoot) ...[
                breadcrumb,
                const Spacer(),
              ] else
                Expanded(child: breadcrumb),
              if (devices != null && devices!.length > 1) ...[
                const SizedBox(width: 12),
                FileTopBarDeviceChips(
                  devices: devices!,
                  activeDevicePaths: activeDevicePaths,
                  onDeviceToggled: onDeviceToggled,
                ),
              ],
              const SizedBox(width: 12),
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
              const SizedBox(width: 8),
              FileTopBarViewChips(
                isGridView: isGridView,
                isUnifiedView: isUnifiedView,
                onToggleView: onToggleView,
                onToggleUnifiedView: onToggleUnifiedView,
              ),
            ],
          );
        },
      ),
    );
  }
}
