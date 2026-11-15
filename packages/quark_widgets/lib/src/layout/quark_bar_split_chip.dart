import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_theme.dart';
import '../theme/quark_tokens.dart';
import 'quark_bar_chip.dart';
import 'quark_bar_icon_button.dart';

/// A [QuarkBarChip] with a second action behind it: the plain tap does the
/// usual thing, and the second action makes the choice the plain tap skips,
/// such as which device an upload goes to (#3194).
///
/// At or above [QuarkBarChip.compactBreakpoint] it is one control, not two
/// buttons side by side: a chip's border, fill, radius, height and focus ring
/// around a label segment and a ▾ segment, split by a hairline in the border
/// color. Each segment is its own tap target with its own ink and focus
/// ring, and the ▾ segment is explained by [secondaryTooltip]. Below the
/// breakpoint, on a phone, the chip renders as it would on its own and a
/// long press runs the second action.
///
/// A null [onSecondaryPressed], or a null [onPressed], renders exactly a
/// plain [QuarkBarChip]: no segment and no long press. Pass null when there
/// is nothing to choose between.
///
/// Key prefixes: the chip takes its own `key`. When that is a
/// `ValueKey<String>`, the ▾ segment is keyed `<key>_choose`.
///
/// ```dart
/// QuarkBarSplitChip(
///   key: const ValueKey('photos_upload'),
///   icon: QuarkIcons.upload_rounded,
///   label: 'Upload',
///   onPressed: upload,
///   onSecondaryPressed: hasDevices ? chooseDeviceAndUpload : null,
/// );
/// ```
class QuarkBarSplitChip extends StatelessWidget {
  /// Creates a chip reading [label] beside [icon], with a second action.
  const QuarkBarSplitChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.onSecondaryPressed,
    this.secondaryTooltip = 'Choose device',
    this.keepLabel = false,
    super.key,
  });

  /// The glyph, from `QuarkIcons`.
  final IconData icon;

  /// The word on the chip.
  final String label;

  /// Runs the plain action. Null renders the chip disabled.
  final VoidCallback? onPressed;

  /// Runs the second action, from the ▾ segment or a long press. Null leaves
  /// a plain chip.
  final VoidCallback? onSecondaryPressed;

  /// What the ▾ segment does, shown on hover and read by screen readers.
  final String secondaryTooltip;

  /// Whether the label stays on a phone, as [QuarkBarChip.keepLabel].
  final bool keepLabel;

  @override
  Widget build(BuildContext context) {
    final secondary = onPressed == null ? null : onSecondaryPressed;
    final compact =
        MediaQuery.sizeOf(context).width < QuarkBarChip.compactBreakpoint;
    if (secondary == null || compact) {
      return QuarkBarChip(
        icon: icon,
        label: label,
        onPressed: onPressed,
        onLongPress: compact ? secondary : null,
        keepLabel: keepLabel,
      );
    }
    final tokens = QuarkTokens.of(context);
    final radius = Radius.circular(tokens.radiusLg);
    // Each segment draws the chip's border round itself, rounded only on its
    // outer side; the ▾ segment then sits one pixel over the label's end edge
    // so the two borders meet in a single hairline divider.
    ButtonStyle segment(BorderRadiusDirectional corners, double padding) =>
        OutlinedButton.styleFrom(
          foregroundColor: tokens.secondaryForeground,
          iconColor: tokens.secondaryForeground,
          backgroundColor: tokens.input,
          shape: RoundedRectangleBorder(borderRadius: corners),
          iconSize: QuarkBarIconButton.glyphSize,
          textStyle: Theme.of(context).textTheme.labelLarge,
          padding: EdgeInsets.symmetric(horizontal: padding),
          minimumSize: const Size(0, QuarkBarIconButton.size),
          // Padded to the 48dp target in height only: padded across, a ▾
          // narrower than 48 would sit apart from the label with a gap, so the
          // ▾ is held to 48 wide below instead.
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: const VisualDensity(
            horizontal: VisualDensity.minimumDensity,
          ),
        ).copyWith(side: QuarkTheme.focusRing(tokens, resting: tokens.border));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = this.key;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: QuarkBarIconButton.tapTargetMargin,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: segment(
              BorderRadiusDirectional.horizontal(start: radius),
              tokens.spacingSm + tokens.spacingXs,
            ),
          ),
          Transform.translate(
            key: key is ValueKey<String>
                ? ValueKey('${key.value}_choose')
                : null,
            offset: Offset(rtl ? 1 : -1, 0),
            child: MergeSemantics(
              child: Tooltip(
                message: secondaryTooltip,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: QuarkBarIconButton.tapTargetSize,
                  ),
                  child: OutlinedButton(
                    onPressed: secondary,
                    style: segment(
                      BorderRadiusDirectional.horizontal(end: radius),
                      tokens.spacingSm,
                    ),
                    // The empty text gives the segment the label's line height,
                    // so both grow together at a large text size (#2606).
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(QuarkIcons.expand_more), Text('')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
