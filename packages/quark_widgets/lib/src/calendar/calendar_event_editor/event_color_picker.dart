import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// A row of round swatches, one per `QuarkTokens.eventColors` entry, the
/// chosen one ringed and checked, so the choice does not rest on color alone.
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (index, color) in tokens.eventColors.indexed)
          Semantics(
            label: index < names.length ? names[index] : 'Color ${index + 1}',
            selected: index == value,
            inMutuallyExclusiveGroup: true,
            button: true,
            excludeSemantics: true,
            child: InkResponse(
              key: ValueKey('event_color_$index'),
              onTap: () => onChanged(index),
              radius: 20,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: index == value
                      ? [
                          BoxShadow(color: tokens.card, spreadRadius: 2),
                          BoxShadow(color: tokens.foreground, spreadRadius: 4),
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
      ],
    );
  }
}
