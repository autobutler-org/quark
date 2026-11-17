import 'package:material_ui/material_ui.dart';
import 'package:quark/models/file_device.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A [DeviceTag] for every device a file or folder is on, each in that
/// device's color: a folder merged from several drives shows them all
/// (#1869). Renders nothing for a node that names no device.
///
/// When every tag does not fit at its full width, it never squeezes them to
/// empty pills (#3936): it shows the first drive and a "+N" tag for the rest,
/// or when even that does not fit, one "N drives" tag. Each summary tag names
/// the drives it stands for in its tooltip and to a screen reader.
///
/// Each tag is keyed `device_tag_<serial>`, the internal drive's serial
/// being empty (`device_tag_`). The "+N" tag is `device_tag_more` and the
/// "N drives" tag `device_tag_summary`.
class FileDeviceTags extends StatelessWidget {
  const FileDeviceTags({
    required this.item,
    this.deviceColors = const {},
    super.key,
  });

  /// The file or folder whose devices are shown.
  final FileNode item;

  /// Each attached device's color by serial, from [DeviceTag.colorsFor] over
  /// every drive on the Quark, so no two drives share one. A serial missing
  /// here is colored among the item's own devices.
  final Map<String, Color> deviceColors;

  @override
  Widget build(BuildContext context) {
    final devices = item.onDevices;
    if (devices.isEmpty) return const SizedBox.shrink();
    final tokens = QuarkTokens.of(context);
    final gap = tokens.spacingXs;
    final colors = {
      ...DeviceTag.colorsFor(context, [for (final d in devices) d.serial]),
      ...deviceColors,
    };
    Widget tag(FileDevice device) => DeviceTag(
      key: ValueKey('device_tag_${device.serial}'),
      label: device.name,
      color: colors[device.serial]!,
    );
    Widget summary(String key, String label, List<FileDevice> standsFor) {
      final names = [for (final d in standsFor) d.name].join(', ');
      return DeviceTag(
        key: ValueKey(key),
        label: label,
        tooltip: names,
        semanticLabel: names,
        color: tokens.mutedForeground,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [
          for (final d in devices) DeviceTag.widthFor(context, d.name),
        ];
        final all =
            widths.fold<double>(0, (sum, w) => sum + w) +
            gap * (devices.length - 1);
        final List<Widget> tags;
        if (devices.length == 1 || all <= constraints.maxWidth) {
          tags = [for (final d in devices) tag(d)];
        } else {
          final more = '+${devices.length - 1}';
          final firstAndMore =
              widths.first + gap + DeviceTag.widthFor(context, more);
          tags = firstAndMore <= constraints.maxWidth
              ? [
                  tag(devices.first),
                  summary('device_tag_more', more, devices.sublist(1)),
                ]
              : [
                  summary(
                    'device_tag_summary',
                    '${devices.length} drives',
                    devices,
                  ),
                ];
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, t) in tags.indexed)
              Flexible(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : gap),
                  child: t,
                ),
              ),
          ],
        );
      },
    );
  }
}
