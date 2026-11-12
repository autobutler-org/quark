import 'package:material_ui/material_ui.dart';

/// A slider for one radius or spacing token, applied as it moves.
///
/// Named for the control rather than the token because `NumberField` is
/// already the record type in `token_fields.dart` that feeds it.
class NumberSlider extends StatelessWidget {
  /// Creates the slider for the token called [name].
  const NumberSlider({
    required this.name,
    required this.value,
    required this.max,
    required this.onChanged,
    super.key,
  });

  /// The token's name, shown above the slider.
  final String name;

  /// The token's current value.
  final double value;

  /// The top of the slider's range.
  final double max;

  /// Called with the new value as the slider moves.
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$name  ${value.toStringAsFixed(0)}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        Slider(
          value: value.clamp(0, max),
          max: max,
          divisions: max.round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
