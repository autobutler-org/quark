import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// A small rounded pill naming the storage device a file or folder is on, in
/// that device's color: beside a Files list row, on a grid tile, and in a
/// per-device group header.
///
/// The fill is a light tint of [color] and the outline is [color]; the label
/// is drawn in [QuarkTokens.foreground] so it stays readable on every device
/// color in every theme. The label is one line and ends in an ellipsis when
/// the tag is squeezed, so a caller in a tight [Row] wraps it in a `Flexible`. A
/// [Tooltip] shows [tooltip] on hover and on long-press, and stays out of the
/// semantics tree: the tag already says [label], and a screen reader reads
/// that full name even when the line is cut short (#3937). It is decoration,
/// not a control, so it takes no callbacks.
///
/// Key prefixes: the caller passes `ValueKey('device_tag_<serial>')`, with an
/// empty serial (`device_tag_`) for the internal drive.
///
/// ```dart
/// DeviceTag(
///   key: ValueKey('device_tag_${device.serial}'),
///   label: device.name,
///   color: DeviceTag.colorFor(context, device.serial),
/// );
/// ```
class DeviceTag extends StatelessWidget {
  /// Creates a tag reading [label] in [color].
  const DeviceTag({
    required this.label,
    required this.color,
    this.tooltip,
    super.key,
  });

  /// The device's display name shown in the tag, cut short with an ellipsis when tight.
  final String label;

  /// The device's color, used for the tag's tint and outline. Pick it with
  /// [colorFor] so a device keeps one color everywhere.
  final Color color;

  /// The tooltip message shown on hover and long-press. Null uses [label].
  final String? tooltip;

  /// A stable color for the device with [serial] (`''` is the internal drive),
  /// picked from [QuarkTokens.eventColors] of the current theme.
  ///
  /// The pick hashes the serial's code units with 32-bit FNV-1a rather than
  /// [String.hashCode], so a device gets the same color on every run and on
  /// both web and the VM. Falls back to [QuarkTokens.primary] when the token
  /// set has no event colors.
  static Color colorFor(BuildContext context, String serial) {
    final tokens = QuarkTokens.of(context);
    final colors = tokens.eventColors;
    if (colors.isEmpty) return tokens.primary;
    var hash = 0x811c9dc5;
    for (final unit in serial.codeUnits) {
      final mixed = hash ^ unit;
      // The FNV prime is 2^24 + 403. Multiplying by its parts keeps every
      // intermediate under 2^53, so web doubles compute what the VM does.
      hash = (mixed * 403 + (mixed & 0xFF) * 0x1000000) & 0xFFFFFFFF;
    }
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // Hover text only. In the semantics tree it merges into the row or tile
    // and web reads it ahead of the file name (#3937). The tag already paints
    // [label], and that full name is what is read when the line is cut short.
    return Tooltip(
      message: tooltip ?? label,
      triggerMode: TooltipTriggerMode.longPress,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacingSm,
              vertical: 2,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: tokens.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
