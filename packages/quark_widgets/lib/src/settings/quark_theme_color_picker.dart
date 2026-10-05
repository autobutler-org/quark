import 'package:flutter/material.dart';

import '../theme/quark_theme_color.dart';
import '../theme/quark_tokens.dart';
import 'quark_theme_color_picker/theme_color_hue_slider.dart';
import 'quark_theme_color_picker/theme_color_swatch.dart';

/// Picks a theme color: a swatch per [QuarkThemeColor.presets] entry, a
/// custom color chosen by hue, and optionally "Use this Quark's default".
///
/// The theme color in use is the caller's state, [value] in and [onChanged]
/// out; save `themeColor.storageValue`. Each swatch previews the theme for
/// the brightness on screen: its chrome color, with a dot of its accent. A
/// custom color is a seed, and the swatch beside the presets shows what the
/// hue under the slider derives to. The picker only holds the hue while the
/// slider is being dragged, and reports once, when it is let go.
///
/// Pass [onUseDefault] to offer following the Quark's own theme color, and
/// [usingDefault] to show that as the choice; [value] is then the theme color
/// being followed, and no swatch is marked.
///
/// Key prefixes: `theme_color_swatch_<name>` on each preset, for example
/// `theme_color_swatch_classic`; `theme_color_custom` on the custom swatch;
/// `theme_color_hue_slider` on the slider; `theme_color_use_default` on the
/// default choice.
///
/// ```dart
/// QuarkThemeColorPicker(
///   value: controller.themeColor,
///   usingDefault: controller.followsQuark,
///   onChanged: (color) => controller.setThemeColor(color.storageValue),
///   onUseDefault: controller.clearThemeColor,
/// );
/// ```
class QuarkThemeColorPicker extends StatefulWidget {
  /// Creates the picker with [value] chosen.
  const QuarkThemeColorPicker({
    required this.value,
    required this.onChanged,
    this.onUseDefault,
    this.usingDefault = false,
    super.key,
  });

  /// The theme color in use. While [usingDefault], the one being followed.
  final QuarkThemeColor value;

  /// Called with the theme color picked: a preset when its swatch is tapped,
  /// or a custom one when the custom swatch is tapped or the slider is let
  /// go. Its `storageValue` is what to save.
  final ValueChanged<QuarkThemeColor> onChanged;

  /// Called when "Use this Quark's default" is tapped. Null hides the choice,
  /// which is what the admin's own picker for that default wants.
  final VoidCallback? onUseDefault;

  /// Whether the person follows the Quark's default rather than a theme color
  /// of their own. Marks the default choice instead of a swatch.
  final bool usingDefault;

  /// The seed the slider yields at [hue] degrees: that hue at a fixed, vivid
  /// saturation and lightness.
  static Color seedForHue(double hue) =>
      HSLColor.fromAHSL(1, hue % 360, 0.8, 0.5).toColor();

  @override
  State<QuarkThemeColorPicker> createState() => _QuarkThemeColorPickerState();
}

class _QuarkThemeColorPickerState extends State<QuarkThemeColorPicker> {
  /// The hue under the thumb while the slider is being dragged.
  double? _dragHue;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final brightness = Theme.of(context).brightness;
    final value = widget.value;
    final onUseDefault = widget.onUseDefault;

    final dragHue = _dragHue;
    // Classic has no seed; its accent stands in for one.
    final hue =
        dragHue ??
        HSLColor.fromColor(
          value.seed ?? value.tokensFor(brightness).primary,
        ).hue;
    final custom = dragHue == null && value.isCustom
        ? value
        : QuarkThemeColor.fromSeed(QuarkThemeColorPicker.seedForHue(hue));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No spacing: each 28px swatch sits in its own 48dp touch target, and
        // the target's margin is the gap.
        Wrap(
          children: [
            for (final (themeColor, preview) in [
              for (final themeColor in [...QuarkThemeColor.presets, custom])
                (themeColor, themeColor.tokensFor(brightness)),
            ])
              ThemeColorSwatch(
                key: ValueKey(
                  themeColor.isCustom
                      ? 'theme_color_custom'
                      : 'theme_color_swatch_${themeColor.name}',
                ),
                chrome: preview.chrome,
                accent: preview.primary,
                checkColor: preview.primaryForeground,
                label: themeColor.label,
                selected:
                    !widget.usingDefault &&
                    (themeColor.isCustom
                        ? value.isCustom
                        : themeColor == value),
                onTap: () => widget.onChanged(themeColor),
              ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 384),
          child: ThemeColorHueSlider(
            hue: hue,
            colorForHue: QuarkThemeColorPicker.seedForHue,
            onChanged: (hue) => setState(() => _dragHue = hue),
            onChangeEnd: (hue) {
              setState(() => _dragHue = null);
              widget.onChanged(
                QuarkThemeColor.fromSeed(QuarkThemeColorPicker.seedForHue(hue)),
              );
            },
          ),
        ),
        if (onUseDefault != null)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacingXs),
            child: ChoiceChip(
              key: const ValueKey('theme_color_use_default'),
              label: const Text("Use this Quark's default"),
              selected: widget.usingDefault,
              onSelected: (_) => onUseDefault(),
            ),
          ),
      ],
    );
  }
}
