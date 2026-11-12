import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A [DeviceTag] for every device a file or folder is on, each in that
/// device's color, in one row that shrinks to fit: a folder merged from
/// several drives shows them all (#1869). Renders nothing for a node that
/// names no device.
///
/// Each tag is keyed `device_tag_<serial>`, the internal drive's serial
/// being empty (`device_tag_`).
class FileDeviceTags extends StatelessWidget {
  const FileDeviceTags({required this.item, super.key});

  /// The file or folder whose devices are shown.
  final FileNode item;

  @override
  Widget build(BuildContext context) {
    final devices = item.onDevices;
    if (devices.isEmpty) return const SizedBox.shrink();
    final gap = QuarkTokens.of(context).spacingXs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, device) in devices.indexed)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
              child: DeviceTag(
                key: ValueKey('device_tag_${device.serial}'),
                label: device.name,
                color: DeviceTag.colorFor(context, device.serial),
              ),
            ),
          ),
      ],
    );
  }
}
