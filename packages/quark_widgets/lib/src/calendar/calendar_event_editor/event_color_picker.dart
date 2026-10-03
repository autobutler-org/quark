import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// A row of round swatches, one per `QuarkTokens.eventColors` entry, the
/// chosen one ringed and checked, so the choice does not rest on color alone.
/// Each swatch is a 48dp target, named for its color to a screen reader.
///
/// Key prefixes: `event_color_<index>` on each swatch.
class EventColorPicker extends StatelessWidget {
  /// Creates the picker with [value] chosen.
  const EventColorPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The index of the chosen color.
  final int value;

  /// Called with the index picked.
  final ValueChanged<int> onChanged;

  /// The names read out for the six colors Quark ships.
  static const List<String> names = [
    'Sky',
    'Green',
    'Amber',
    'Violet',
    'Rose',
    'Slate',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // No spacing: each 28px swatch sits in its own 48dp touch target
    // (#2605), and the target's margin is the gap.
    return Wrap(
      children: [
        for (final (index, color) in tokens.eventColors.indexed)
          Semantics(
            label: index < names.length ? names[index] : 'Color ${index + 1}',
            selected: index == value,
            inMutuallyExclusiveGroup: true,
            button: true,
            excludeSemantics: true,
            // Excluding the child's semantics drops its tap too, so the node
            // carries its own, or a screen reader cannot press it (#2603).
            onTap: () => onChanged(index),
            child: InkResponse(
              key: ValueKey('event_color_$index'),
              onTap: () => onChanged(index),
              radius: 20,
              child: SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: index == value
                          ? [
                              BoxShadow(color: tokens.card, spreadRadius: 2),
                              BoxShadow(
                                color: tokens.foreground,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: index == value
                        ? Icon(
                            QuarkIcons.check_rounded,
                            size: 16,
                            // Dark on a light swatch, light on a dark one.
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.light
                                ? QuarkTokens.dark.background
                                : QuarkTokens.light.card,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
