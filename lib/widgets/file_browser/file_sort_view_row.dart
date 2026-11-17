import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The row over the Files page's phone list (#4226): the folder path beside a
/// "Sort and view" chip, which opens a [FileSortViewSheet] of the sorts a
/// one-line row can show (Name, Modified, Size), both orders, list or grid,
/// per-device grouping and, with more than one drive, which drives to show.
///
/// It is the phone's stand-in for the column headers and the bar's Views
/// menu. Each choice applies at once and closes the sheet.
///
/// Probe keys: those of [FileSortViewBar] and [FileSortViewSheet].
class FileSortViewRow extends StatelessWidget {
  const FileSortViewRow({
    required this.lead,
    required this.sortColumn,
    required this.sortDirection,
    required this.isGridView,
    required this.isUnifiedView,
    required this.onSortChanged,
    required this.onToggleView,
    required this.onToggleUnifiedView,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    super.key,
  });

  /// The sorts the sheet offers. A sort chosen on a wide window and not among
  /// them still shows on the chip.
  static const sortOptions = [
    SortColumn.name,
    SortColumn.modified,
    SortColumn.size,
  ];

  /// Where the listing is: the folder breadcrumb.
  final Widget lead;
  final SortColumn sortColumn;
  final SortDirection sortDirection;
  final bool isGridView;

  /// Whether every drive's files are merged; false groups them per device.
  final bool isUnifiedView;
  final void Function(SortColumn column, SortDirection direction) onSortChanged;
  final VoidCallback onToggleView;
  final VoidCallback onToggleUnifiedView;

  /// The drives the listing can be narrowed to. Fewer than two offers none.
  final List<StorageDevice>? devices;

  /// The device paths shown now; null shows every one.
  final Set<String>? activeDevicePaths;

  /// Shows or hides one drive by its device path.
  final ValueChanged<String>? onDeviceToggled;

  Future<void> _open(BuildContext context) => showQuarkSheet<void>(
    context,
    title: 'Sort and view',
    builder: (sheetContext) {
      // Each choice applies, then the sheet closes.
      void then(VoidCallback apply) {
        Navigator.of(sheetContext).pop();
        apply();
      }

      final onDeviceToggled = this.onDeviceToggled;
      return FileSortViewSheet(
        sortOptions: [for (final column in sortOptions) column.label],
        selectedSort: sortColumn.label,
        ascending: sortDirection == SortDirection.asc,
        isGridView: isGridView,
        isGroupedByDevice: !isUnifiedView,
        devices: [
          for (final device in devices ?? const <StorageDevice>[])
            FileDeviceChoice(
              id: device.devicePath,
              label: device.name.isNotEmpty ? device.name : device.mountPoint,
              selected: activeDevicePaths?.contains(device.devicePath) ?? true,
            ),
        ],
        onSortSelected: (label) => then(
          () => onSortChanged(
            sortOptions.firstWhere((c) => c.label == label),
            sortDirection,
          ),
        ),
        onAscendingChanged: (ascending) => then(
          () => onSortChanged(
            sortColumn,
            ascending ? SortDirection.asc : SortDirection.desc,
          ),
        ),
        onGridViewChanged: (grid) => then(() {
          if (grid != isGridView) onToggleView();
        }),
        onGroupedByDeviceChanged: (grouped) => then(() {
          if (grouped == isUnifiedView) onToggleUnifiedView();
        }),
        onDeviceToggled: onDeviceToggled == null
            ? null
            : (id) => then(() => onDeviceToggled(id)),
      );
    },
  );

  @override
  Widget build(BuildContext context) => FileSortViewBar(
    lead: lead,
    sortLabel: sortColumn.label,
    ascending: sortDirection == SortDirection.asc,
    onPressed: () => _open(context),
  );
}
