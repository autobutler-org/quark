import 'package:flutter/material.dart';
import 'package:quark_slides/quark_slides.dart';

/// A field for a custom color as `#RRGGBB` hex, under a slide color
/// palette's swatches. Enter, or leaving the field, sets the color when the
/// text is one; anything else shows the format to type and sets nothing.
///
/// It keeps its own text while it has focus and shows [color] otherwise, so
/// a selection change elsewhere does not overwrite what is being typed.
///
/// Key prefixes: none of its own; the palette passes `<key>_hex`.
class SlideHexField extends StatefulWidget {
  /// A field showing [color], calling [onChanged] with what is typed.
  const SlideHexField({
    required this.color,
    required this.onChanged,
    this.label = 'Custom color',
    super.key,
  });

  /// The color in use; null shows an empty field.
  final SlideColor? color;

  /// Sets the color; null renders the field disabled.
  final ValueChanged<SlideColor>? onChanged;

  /// The field's label, which a screen reader reads.
  final String label;

  /// Reads `#RRGGBB` or `RRGGBB`, case-insensitive; null for anything else.
  static SlideColor? parse(String text) {
    final hex = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return SlideColor(0xFF000000 | int.parse(hex, radix: 16));
  }

  /// [color] as `#RRGGBB`, its alpha dropped.
  static String format(SlideColor color) =>
      SlideColor(color.argb | 0xFF000000).toHex();

  @override
  State<SlideHexField> createState() => _SlideHexFieldState();
}

class _SlideHexFieldState extends State<SlideHexField> {
  late final _text = TextEditingController(text: _shown);
  final _focus = FocusNode();
  bool _invalid = false;

  /// The text last submitted, so Enter and the focus loss after it submit
  /// once between them.
  String? _submitted;

  String get _shown {
    final color = widget.color;
    return color == null ? '' : SlideHexField.format(color);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_text.text);
    });
  }

  @override
  void didUpdateWidget(SlideHexField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.color != widget.color) {
      _text.text = _shown;
      _submitted = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text == _submitted) return;
    _submitted = text;
    if (text.trim().isEmpty || text == _shown) {
      setState(() => _invalid = false);
      return;
    }
    final color = SlideHexField.parse(text);
    setState(() => _invalid = color == null);
    if (color != null) widget.onChanged?.call(color);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    enabled: widget.onChanged != null,
    maxLength: 7,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: '#3366FF',
      counterText: '',
      errorText: _invalid ? 'Type a color as #RRGGBB' : null,
      isDense: true,
    ),
    onSubmitted: _submit,
  );
}
