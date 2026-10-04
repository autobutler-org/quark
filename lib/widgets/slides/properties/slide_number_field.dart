import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
class SlideNumberField extends StatefulWidget {
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
  State<SlideNumberField> createState() => _SlideNumberFieldState();
}

class _SlideNumberFieldState extends State<SlideNumberField> {
  late final _text = TextEditingController(
    text: SlideNumberField.format(widget.value),
  );
  final _focus = FocusNode();

  /// The text last submitted, so Enter and the focus loss after it submit
  /// once between them.
  String? _submitted;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(SlideNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _text.text = SlideNumberField.format(widget.value);
      _submitted = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text == _submitted) return;
    _submitted = _text.text;
    final number = double.tryParse(_text.text.trim());
    if (number == null || !number.isFinite) {
      _text.text = SlideNumberField.format(widget.value);
      return;
    }
    if (number != widget.value) widget.onSubmitted?.call(number);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    readOnly: widget.onSubmitted == null,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
    decoration: InputDecoration(
      labelText: widget.label,
      suffixText: widget.unit.isEmpty ? null : widget.unit,
      isDense: true,
    ),
    onSubmitted: (_) => _submit(),
  );
}
