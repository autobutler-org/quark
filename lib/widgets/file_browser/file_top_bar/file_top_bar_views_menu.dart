import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_menu_radio_item.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_menu_section_header.dart';
import 'package:quark_icons/quark_icons.dart';

/// What the compact layout's labeled Views menu holds: everything the wide
/// layout spreads across the path row — device filter, layout and grouping.
/// The menu itself, and the chip that opens it, belong to the bar's
/// `QuarkAppBarBottom`.
///
/// Probe keys: `file_top_bar_views_list`, `file_top_bar_views_grid` and
/// `file_top_bar_views_grouping`.
class FileTopBarViewsMenu extends StatelessWidget {
  const FileTopBarViewsMenu({
    required this.isGridView,
    required this.isUnifiedView,
    required this.onToggleView,
    required this.onToggleUnifiedView,
    this.devices,
    this.activeDevicePaths,
    this.onDeviceToggled,
    super.key,
  });

  final bool isGridView;
  final bool isUnifiedView;
  final VoidCallback onToggleView;
  final VoidCallback onToggleUnifiedView;
  final List<StorageDevice>? devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDeviceFilter = devices != null && devices!.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Device filter section ──
        if (hasDeviceFilter) ...[
          const TopBarMenuSectionHeader(title: 'Filter devices'),
          ...devices!.map((device) {
            final isSelected =
                activeDevicePaths?.contains(device.devicePath) ?? true;
            final label = device.name.isNotEmpty
                ? device.name
                : device.mountPoint;
            return CheckboxListTile(
              value: isSelected,
              dense: true,
              title: Text(label, style: const TextStyle(fontSize: 14)),
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              onChanged: onDeviceToggled != null
                  ? (_) => onDeviceToggled!(device.devicePath)
                  : null,
            );
          }),
          const Divider(height: 1, indent: 16, endIndent: 16),
        ],

        // ── Layout section ──
        const TopBarMenuSectionHeader(title: 'Layout'),
        TopBarMenuRadioItem(
          key: const ValueKey('file_top_bar_views_list'),
          icon: QuarkIcons.view_list_rounded,
          label: 'List',
          selected: !isGridView,
          onTap: () {
            if (isGridView) onToggleView();
          },
        ),
        TopBarMenuRadioItem(
          key: const ValueKey('file_top_bar_views_grid'),
          icon: QuarkIcons.grid_view_rounded,
          label: 'Grid',
          selected: isGridView,
          onTap: () {
            if (!isGridView) onToggleView();
          },
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),

        // ── Device grouping section ──
        const TopBarMenuSectionHeader(title: 'Grouping'),
        ListTile(
          key: const ValueKey('file_top_bar_views_grouping'),
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            isUnifiedView
                ? QuarkIcons.folder_copy_outlined
                : QuarkIcons.device_hub_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          title: Text(
            isUnifiedView ? 'Unified' : 'Per-device',
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            ViewGroupingCopy.forMode(isUnified: isUnifiedView),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          trailing: Switch.adaptive(
            value: isUnifiedView,
            onChanged: (_) => onToggleUnifiedView(),
          ),
          onTap: onToggleUnifiedView,
        ),
      ],
    );
  }
}
