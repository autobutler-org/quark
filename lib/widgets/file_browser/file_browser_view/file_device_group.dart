import 'package:flutter/material.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One device's section of the per-device Files view, in the list, the grid
/// and search results alike (#1870): a header with the device's tag and how
/// many items it holds, expanded to [children] by default.
///
/// The header's tag is keyed `device_group_tag_<serial>`.
class FileDeviceGroup extends StatelessWidget {
  const FileDeviceGroup({
    required this.device,
    required this.itemCount,
    required this.children,
    super.key,
  });

  /// The device the section lists.
  final FileDevice device;

  /// How many items the section holds, for the header's count.
  final int itemCount;

  /// The section's items: list rows, or one grid of tiles.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(QuarkIcons.storage_rounded),
      title: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DeviceTag(
          key: ValueKey('device_group_tag_${device.serial}'),
          label: device.name,
          color: DeviceTag.colorFor(context, device.serial),
        ),
      ),
      subtitle: Text('$itemCount item${itemCount == 1 ? '' : 's'}'),
      children: children,
    );
  }
}
