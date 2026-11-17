import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// A small rounded pill naming the storage device a file or folder is on, in
/// that device's color: beside a Files list row, on a grid tile, and in a
/// per-device group header.
///
/// The fill is a light tint of [color] and the outline is [color]; the label
/// is drawn in [QuarkTokens.foreground] so it stays readable on every device
/// color in every theme. The label is one line and ends in an ellipsis when
/// the tag is squeezed, so a caller in a tight [Row] wraps it in a `Flexible`,
/// or measures it first with [widthFor] and shows fewer tags (#3936).
///
/// A [Tooltip] shows [tooltip] on hover, on long-press, and on a tap: the tap
/// stops at the tag, so checking which drive an item is on never opens the
/// row or tile under it. The tooltip stays out of the semantics tree: the tag
/// already says [semanticLabel], and a screen reader reads that full name
/// even when the line is cut short (#3937). It takes no callbacks.
///
/// Key prefixes: the caller passes `ValueKey('device_tag_<serial>')`, with an
/// empty serial (`device_tag_`) for the internal drive.
///
/// ```dart
/// final colors = DeviceTag.colorsFor(context, [for (final d in devices) d.serial]);
/// DeviceTag(
///   key: ValueKey('device_tag_${device.serial}'),
///   label: device.name,
///   color: colors[device.serial]!,
/// );
/// ```
class DeviceTag extends StatefulWidget {
  /// Creates a tag reading [label] in [color].
  const DeviceTag({
    required this.label,
    required this.color,
    this.tooltip,
    this.semanticLabel,
    super.key,
  });

  /// The device's display name shown in the tag, cut short with an ellipsis when tight.
  final String label;

  /// The device's color, used for the tag's tint and outline. Pick it with
  /// [colorsFor] so the drives on one Quark never share a color.
  final Color color;

  /// The tooltip message shown on hover, tap and long-press. Null uses [label].
  final String? tooltip;

  /// What a screen reader reads for the tag. Null uses [label]; a summary tag
  /// such as "+2" passes the drive names it stands for.
  final String? semanticLabel;

  /// The horizontal padding inside the tag's outline, on each side.
  static double _paddingOf(QuarkTokens tokens) => tokens.spacingSm;

  static TextStyle _styleOf(QuarkTokens tokens) => TextStyle(
    color: tokens.foreground,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// The width a tag reading [label] takes when nothing squeezes it, at the
  /// current text scale: the label and its padding.
  static double widthFor(BuildContext context, String label) {
    final tokens = QuarkTokens.of(context);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(_styleOf(tokens)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // The outline is painted over the padding, so it adds no width.
    return (width + _paddingOf(tokens) * 2).ceilToDouble();
  }

  /// The palette slot [serial] hashes to: 32-bit FNV-1a over its code units
  /// rather than [String.hashCode], so it is the same on every run and on
  /// both web and the VM.
  static int _slotOf(String serial, int slots) {
    var hash = 0x811c9dc5;
    for (final unit in serial.codeUnits) {
      final mixed = hash ^ unit;
      // The FNV prime is 2^24 + 403. Multiplying by its parts keeps every
      // intermediate under 2^53, so web doubles compute what the VM does.
      hash = (mixed * 403 + (mixed & 0xFF) * 0x1000000) & 0xFFFFFFFF;
    }
    return hash % slots;
  }

  /// A color for the device with [serial] (`''` is the internal drive) alone,
  /// picked from [QuarkTokens.eventColors] of the current theme by a stable
  /// hash. Two serials can land on the same color, so wherever more than one
  /// device can show, use [colorsFor]. Falls back to [QuarkTokens.primary]
  /// when the token set has no event colors.
  static Color colorFor(BuildContext context, String serial) =>
      colorsFor(context, [serial])[serial]!;

  /// A color for each of [serials], the devices attached to one Quark in
  /// their listing order (`''` is the internal drive).
  ///
  /// Up to `eventColors.length` devices never share a color (#3936). Each
  /// device takes the slot its serial hashes to, as [colorFor] would, unless
  /// a device earlier in [serials] holds it; then it takes the next free
  /// slot. Only devices past the palette's size fall back to the hash alone.
  /// Falls back to [QuarkTokens.primary] when the token set has no event
  /// colors.
  static Map<String, Color> colorsFor(
    BuildContext context,
    Iterable<String> serials,
  ) {
    final tokens = QuarkTokens.of(context);
    final colors = tokens.eventColors;
    final result = <String, Color>{};
    final taken = <int>{};
    for (final serial in serials) {
      if (result.containsKey(serial)) continue;
      if (colors.isEmpty) {
        result[serial] = tokens.primary;
        continue;
      }
      var slot = _slotOf(serial, colors.length);
      if (taken.length < colors.length) {
        while (taken.contains(slot)) {
          slot = (slot + 1) % colors.length;
        }
        taken.add(slot);
      }
      result[serial] = colors[slot];
    }
    return result;
  }

  @override
  State<DeviceTag> createState() => _DeviceTagState();
}

class _DeviceTagState extends State<DeviceTag> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // Hover text only. In the semantics tree it merges into the row or tile
    // and web reads it ahead of the file name (#3937). The tag carries its
    // full name as its own label, which is what is read when the line is cut
    // short.
    return Tooltip(
      key: _tooltipKey,
      message: widget.tooltip ?? widget.label,
      triggerMode: TooltipTriggerMode.longPress,
      excludeFromSemantics: true,
      // A tap shows the name too, and stops here rather than opening the
      // item the tag sits on (#3936).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        child: Semantics(
          label: widget.semanticLabel ?? widget.label,
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.18),
              border: Border.all(color: widget.color),
              borderRadius: BorderRadius.circular(tokens.radiusLg),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DeviceTag._paddingOf(tokens),
                vertical: 2,
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: DeviceTag._styleOf(tokens),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
