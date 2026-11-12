import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import 'quark_bar_chip.dart';
import 'quark_bar_icon_button.dart';

/// A [QuarkBarChip] with a second action behind it: the plain tap does the
/// usual thing, and the second action makes the choice the plain tap skips,
/// such as which device an upload goes to (#3194).
///
/// At or above [QuarkBarChip.compactBreakpoint] the second action is a ▾
/// segment beside the chip, a [QuarkBarIconButton] explained by
/// [secondaryTooltip]. Below it, on a phone, the chip renders as it would on
/// its own and a long press runs the second action.
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
    final chip = QuarkBarChip(
      icon: icon,
      label: label,
      onPressed: onPressed,
      onLongPress: compact ? secondary : null,
      keepLabel: keepLabel,
    );
    if (secondary == null || compact) return chip;
    final key = this.key;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        QuarkBarIconButton(
          key: key is ValueKey<String> ? ValueKey('${key.value}_choose') : null,
          icon: QuarkIcons.expand_more_rounded,
          tooltip: secondaryTooltip,
          onPressed: secondary,
        ),
      ],
    );
  }
}
