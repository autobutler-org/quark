import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The custom-color control in a `QuarkThemeColorPicker`: a stock [Slider] over a
/// strip of the hues it travels through, from 0 to 360 degrees.
///
/// It holds nothing. [hue] comes in, and the parent hears every move through
/// [onChanged] and the settled value through [onChangeEnd].
///
/// Key prefixes: `theme_color_hue_slider` on the slider.
class ThemeColorHueSlider extends StatelessWidget {
  /// Creates the slider at [hue].
  const ThemeColorHueSlider({
    required this.hue,
    required this.colorForHue,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  /// The hue the thumb sits at, in degrees from 0 to 360.
  final double hue;

  /// The color the strip paints at a hue, so it shows what a hue picks.
  final Color Function(double hue) colorForHue;

  /// Called with the hue on every move of the thumb.
  final ValueChanged<double> onChanged;

  /// Called with the hue the thumb is let go at.
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Center(
            child: Padding(
              // The slider keeps its track this far in from each end, to
              // leave room for the thumb's overlay.
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  gradient: LinearGradient(
                    colors: [
                      for (var hue = 0.0; hue <= 360; hue += 30)
                        colorForHue(hue),
                    ],
                  ),
                ),
                child: const SizedBox(height: 8, width: double.infinity),
              ),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            // The strip behind is the track.
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: tokens.foreground,
            overlayColor: tokens.foreground.withValues(alpha: 0.12),
          ),
          child: Semantics(
            container: true,
            label: 'Custom color hue',
            child: Slider(
              key: const ValueKey('theme_color_hue_slider'),
              value: hue.clamp(0, 360),
              max: 360,
              semanticFormatterCallback: (value) => '${value.round()} degrees',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}
