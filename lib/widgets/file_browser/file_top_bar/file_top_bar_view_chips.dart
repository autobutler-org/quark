import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_chip.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_segmented_toggle.dart';
import 'package:quark_icons/quark_icons.dart';

/// The wide layout's list/grid switch and device-grouping toggle.
class FileTopBarViewChips extends StatelessWidget {
  const FileTopBarViewChips({
    required this.isGridView,
    required this.isUnifiedView,
    required this.onToggleView,
    required this.onToggleUnifiedView,
    super.key,
  });

  final bool isGridView;
  final bool isUnifiedView;
  final VoidCallback onToggleView;
  final VoidCallback onToggleUnifiedView;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TopBarSegmentedToggle(
          segments: const [
            (icon: QuarkIcons.view_list_rounded, label: 'List'),
            (icon: QuarkIcons.grid_view_rounded, label: 'Grid'),
          ],
          selectedIndex: isGridView ? 1 : 0,
          onSelected: (index) {
            final wantGrid = index == 1;
            if (wantGrid != isGridView) {
              onToggleView();
            }
          },
        ),
        const SizedBox(width: 4),
        TopBarChip(
          icon: isUnifiedView
              ? QuarkIcons.folder_copy_outlined
              : QuarkIcons.device_hub_outlined,
          label: isUnifiedView ? 'Unified' : 'Per-device',
          tooltip: ViewGroupingCopy.forMode(isUnified: isUnifiedView),
          onTap: onToggleUnifiedView,
          active: isUnifiedView,
        ),
      ],
    );
  }
}
