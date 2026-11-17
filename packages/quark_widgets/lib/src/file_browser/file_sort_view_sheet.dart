import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/file_device_choice.dart';
import '../theme/quark_tokens.dart';

/// The body of the "Sort and view" sheet a phone's file list opens from its
/// `FileSortViewBar` (#4226): what to sort by, which way, list or grid, and,
/// when the caller offers them, per-device grouping and which drives to show.
///
/// Every row reports its choice and changes nothing itself; the caller
/// applies it, and usually closes the sheet. Each row is a full-width 48dp
/// target, and a chosen one carries a check and reads as selected.
///
/// Key prefixes: `file_sort_view_sort_<option>` per sort option, lower-cased
/// with spaces as underscores (`file_sort_view_sort_name`),
/// `file_sort_view_ascending`, `file_sort_view_descending`,
/// `file_sort_view_list`, `file_sort_view_grid`, `file_sort_view_grouping`,
/// and `file_sort_view_device_<id>` per [FileDeviceChoice].
///
/// ```dart
/// showQuarkSheet<void>(
///   context,
///   title: 'Sort and view',
///   builder: (sheetContext) => FileSortViewSheet(
///     sortOptions: const ['Name', 'Modified', 'Size'],
///     selectedSort: 'Name',
///     ascending: true,
///     isGridView: false,
///     onSortSelected: setSort,
///     onAscendingChanged: setAscending,
///     onGridViewChanged: setGridView,
///   ),
/// );
/// ```
class FileSortViewSheet extends StatelessWidget {
  /// Creates the sheet's body with [selectedSort] chosen among [sortOptions].
  const FileSortViewSheet({
    required this.sortOptions,
    required this.selectedSort,
    required this.ascending,
    required this.isGridView,
    required this.onSortSelected,
    required this.onAscendingChanged,
    required this.onGridViewChanged,
    this.isGroupedByDevice,
    this.onGroupedByDeviceChanged,
    this.devices = const [],
    this.onDeviceToggled,
    super.key,
  });

  /// What the list can be sorted by, in order, each its own label.
  final List<String> sortOptions;

  /// The entry of [sortOptions] the list is sorted by now. One that is not
  /// among them leaves every sort row unchecked.
  final String selectedSort;

  /// Whether the sort runs ascending.
  final bool ascending;

  /// Whether the listing is a grid rather than a list.
  final bool isGridView;

  /// Called with the sort option that was tapped.
  final ValueChanged<String> onSortSelected;

  /// Called with true for Ascending, false for Descending.
  final ValueChanged<bool> onAscendingChanged;

  /// Called with true for Grid, false for List.
  final ValueChanged<bool> onGridViewChanged;

  /// Whether the listing is grouped under each drive. Read only when
  /// [onGroupedByDeviceChanged] is set.
  final bool? isGroupedByDevice;

  /// Called with the grouping the switch was flipped to. Null leaves the
  /// grouping row out.
  final ValueChanged<bool>? onGroupedByDeviceChanged;

  /// The drives the listing can be narrowed to. Fewer than two leaves the
  /// section out: there is nothing to choose between.
  final List<FileDeviceChoice> devices;

  /// Called with the [FileDeviceChoice.id] of the drive tapped.
  final ValueChanged<String>? onDeviceToggled;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onGrouped = onGroupedByDeviceChanged;
    final onDevice = onDeviceToggled;

    Widget header(String title) => Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacingMd,
        tokens.spacingMd,
        tokens.spacingMd,
        tokens.spacingXs,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: tokens.mutedForeground),
      ),
    );

    Widget choice({
      required String key,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) => Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        key: ValueKey(key),
        minTileHeight: 48,
        leading: icon == null ? null : Icon(icon, size: 20),
        title: Text(label),
        trailing: selected
            ? Icon(QuarkIcons.check, color: tokens.primary)
            : null,
        selected: selected,
        onTap: onTap,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header('Sort by'),
        for (final option in sortOptions)
          choice(
            key:
                'file_sort_view_sort_'
                '${option.toLowerCase().replaceAll(' ', '_')}',
            label: option,
            selected: option == selectedSort,
            onTap: () => onSortSelected(option),
          ),
        header('Order'),
        choice(
          key: 'file_sort_view_ascending',
          label: 'Ascending',
          icon: QuarkIcons.arrow_upward_rounded,
          selected: ascending,
          onTap: () => onAscendingChanged(true),
        ),
        choice(
          key: 'file_sort_view_descending',
          label: 'Descending',
          icon: QuarkIcons.arrow_downward_rounded,
          selected: !ascending,
          onTap: () => onAscendingChanged(false),
        ),
        header('Layout'),
        choice(
          key: 'file_sort_view_list',
          label: 'List',
          icon: QuarkIcons.view_list_rounded,
          selected: !isGridView,
          onTap: () => onGridViewChanged(false),
        ),
        choice(
          key: 'file_sort_view_grid',
          label: 'Grid',
          icon: QuarkIcons.grid_view,
          selected: isGridView,
          onTap: () => onGridViewChanged(true),
        ),
        if (onGrouped != null)
          SwitchListTile.adaptive(
            key: const ValueKey('file_sort_view_grouping'),
            secondary: const Icon(QuarkIcons.device_hub_outlined, size: 20),
            title: const Text('Group by device'),
            value: isGroupedByDevice ?? false,
            onChanged: onGrouped,
          ),
        if (devices.length > 1) ...[
          header('Devices'),
          for (final device in devices)
            CheckboxListTile(
              key: ValueKey('file_sort_view_device_${device.id}'),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(device.label),
              value: device.selected,
              onChanged: onDevice == null ? null : (_) => onDevice(device.id),
            ),
        ],
        SizedBox(height: tokens.spacingSm),
      ],
    );
  }
}
