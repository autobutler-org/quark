import 'package:flutter/material.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_columns_button.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide layout's list/grid switch, device-grouping toggle and column
/// picker.
///
/// Probe keys: `bar_segment_list`, `bar_segment_grid` and
/// `file_top_bar_grouping`, plus those of [FileTopBarColumnsButton].
class FileTopBarViewChips extends StatelessWidget {
  const FileTopBarViewChips({
    required this.isGridView,
    required this.isUnifiedView,
    required this.onToggleView,
    required this.onToggleUnifiedView,
    this.columns = const {},
    this.onColumnToggled,
    super.key,
  });

  final bool isGridView;
  final bool isUnifiedView;
  final VoidCallback onToggleView;
  final VoidCallback onToggleUnifiedView;

  /// The list columns currently shown.
  final Set<FileListColumn> columns;

  /// Shows or hides a list column. Null disables the picker.
  final FileListColumnToggle? onColumnToggled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: QuarkTokens.of(context).spacingXs,
      children: [
        QuarkBarSegmentedToggle(
          segments: const [
            QuarkBarSegment(
              id: 'list',
              icon: QuarkIcons.view_list_rounded,
              label: 'List',
            ),
            QuarkBarSegment(
              id: 'grid',
              icon: QuarkIcons.grid_view_rounded,
              label: 'Grid',
            ),
          ],
          selectedId: isGridView ? 'grid' : 'list',
          onSelected: (id) {
            if ((id == 'grid') != isGridView) onToggleView();
          },
        ),
        QuarkBarChip(
          key: const ValueKey('file_top_bar_grouping'),
          icon: isUnifiedView
              ? QuarkIcons.folder_copy_outlined
              : QuarkIcons.device_hub_outlined,
          label: isUnifiedView ? 'Unified' : 'Per-device',
          tooltip: ViewGroupingCopy.forMode(isUnified: isUnifiedView),
          onPressed: onToggleUnifiedView,
          active: isUnifiedView,
        ),
        FileTopBarColumnsButton(
          columns: columns,
          onColumnToggled: onColumnToggled,
        ),
      ],
    );
  }
}
