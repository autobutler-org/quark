import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_actions.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_upload_chip.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_breadcrumb.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_device_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_select_button.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_views_menu.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The lower half of the top bar: where the user is, and what they can do
/// here, as a [QuarkAppBarBottom].
///
/// Search and Select are pinned at every width, so a phone's top row fits
/// beside the app-wide controls (#3454), as Photos' library row carries its
/// Search.
///
/// On a wide bar the device filter, the create chips and the view toggles sit
/// beside the breadcrumb. Below [collapseBreakpoint] they give way to the
/// labeled Views menu, and creating moves to the floating button.
///
/// The column picker is live only while a list is on screen: the grid has no
/// columns, except per device, where the listing is a list whatever the
/// layout switch says.
///
/// Probe keys: `file_top_bar_search`, plus those of [FileTopBarSelectButton],
/// [FileTopBarActions] and [FileTopBarViewsMenu].
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
    required this.onOpenSearch,
    this.onPathSelected,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    this.onShowUploadProgressPressed,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    this.columns = const {},
    this.onColumnToggled,
    this.onStartSelection,
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
  final DeviceWriteCallback onUploadPressed;
  final DeviceWriteCallback onCreateFolderPressed;
  final VoidCallback onNewFilePressed;

  /// Swaps this row for the search field.
  final VoidCallback onOpenSearch;
  final ValueChanged<String>? onPathSelected;
  final DeviceWriteCallback? onUploadPhotosPressed;
  final DeviceWriteCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;
  final VoidCallback? onShowUploadProgressPressed;
  final List<StorageDevice>? devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  /// The list columns currently shown.
  final Set<FileListColumn> columns;

  /// Shows or hides a list column.
  final FileListColumnToggle? onColumnToggled;

  /// Enters multi-select. Null leaves Select out.
  final VoidCallback? onStartSelection;

  /// The width below which the chips give way to the Views menu. Files has
  /// more actions than the bar's default breakpoint leaves room for: at 1200
  /// they squeezed the breadcrumb to 39 pixels (#1871). The page's create
  /// button shows below it too.
  static const double collapseBreakpoint = 1240;

  /// [collapseBreakpoint] for a bar listing [devices]: with more than one,
  /// Upload's and New folder's choose-device segments need room of their own
  /// (#3194).
  static double collapseBreakpointFor(List<StorageDevice>? devices) =>
      collapseBreakpoint +
      (devices != null && devices.length > 1
          ? 2 * QuarkBarIconButton.tapTargetSize
          : 0);

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
    final canChooseDevice = devices != null && devices.length > 1;
    final onStartSelection = this.onStartSelection;
    final onColumnToggled = isGridView && isUnifiedView
        ? null
        : this.onColumnToggled;
    return QuarkAppBarBottom(
      collapseBelow: collapseBreakpointFor(devices),
      // At the root the breadcrumb is only the home icon: let the pill shrink
      // to it rather than stretch across the row.
      lead: currentPath.isEmpty
          ? Align(alignment: Alignment.centerLeft, child: breadcrumb)
          : breadcrumb,
      pinnedActions: [
        QuarkBarIconButton(
          key: const ValueKey('file_top_bar_search'),
          icon: QuarkIcons.search_rounded,
          tooltip: 'Search',
          onPressed: onOpenSearch,
        ),
        if (onStartSelection != null)
          FileTopBarSelectButton(onPressed: onStartSelection),
      ],
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
          onShowUploadProgressPressed: onShowUploadProgressPressed,
          canChooseDevice: canChooseDevice,
        ),
        FileTopBarViewChips(
          isGridView: isGridView,
          isUnifiedView: isUnifiedView,
          onToggleView: onToggleView,
          onToggleUnifiedView: onToggleUnifiedView,
          columns: columns,
          onColumnToggled: onColumnToggled,
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
          columns: columns,
          onColumnToggled: onColumnToggled,
        ),
      ],
    );
  }
}
