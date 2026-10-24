import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/slides/properties/slide_commit_field.dart';

/// A numeric field in the slide properties panel — X, Y, width, height,
/// rotation — labeled [label] with its [unit] after the number.
///
/// Typing does nothing until Enter or leaving the field, which calls
/// [onSubmitted] once with the number, so a value typed digit by digit is
/// one undo step. Text that is not a number puts [value] back. While the
/// field has focus it keeps what is being typed; otherwise it shows
/// [value], so a drag on the canvas updates it.
///
/// Key prefixes: none of its own; the panel passes `slide_prop_<name>`.
class SlideNumberField extends StatelessWidget {
  /// A field for [value], called [label].
  const SlideNumberField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.unit = '',
    super.key,
  });

  /// What the number is, read by a screen reader.
  final String label;

  /// The number shown.
  final double value;

  /// The unit after the number, such as "°".
  final String unit;

  /// Sets the number; null renders the field read-only.
  final ValueChanged<double>? onSubmitted;

  /// [value] as the field shows it: whole numbers without decimals, others
  /// to one place.
  static String format(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => SlideCommitField(
    text: format(value),
    onCommit: (typed) {
      final number = double.tryParse(typed.trim());
      if (number == null || !number.isFinite) return format(value);
      if (number != value) onSubmitted?.call(number);
      return null;
    },
    builder: (context, controller, focusNode, commit) => TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: onSubmitted == null,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.isEmpty ? null : unit,
        isDense: true,
      ),
      onSubmitted: (_) => commit(),
    ),
  );
}
