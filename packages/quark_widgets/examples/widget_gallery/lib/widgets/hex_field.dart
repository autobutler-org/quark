import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../token_fields.dart';

/// A hex entry for one color token, applied when the field is submitted.
class HexField extends StatefulWidget {
  /// Creates the field for the token called [name].
  const HexField({
    required this.name,
    required this.value,
    required this.onSubmitted,
    super.key,
  });

  /// The token's name, shown as the field label.
  final String name;

  /// The token's current color, shown in the swatch and as the initial text.
  final Color value;

  /// Called with the parsed color when the field is submitted. Unparseable
  /// text resets the field instead.
  final ValueChanged<Color> onSubmitted;

  @override
  State<HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<HexField> {
  late final TextEditingController _controller = TextEditingController(
    text: toHex(widget.value),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final color = parseHex(text);
    if (color == null) {
      _controller.text = toHex(widget.value);
      return;
    }
    widget.onSubmitted(color);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacingSm),
      child: TextField(
        controller: _controller,
        onSubmitted: _submit,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.name,
          prefixIcon: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            // The prefix slot hands down loose constraints, so the swatch needs
            // an explicit height or it collapses to its 2px border and the
            // color it is meant to show is invisible.
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: widget.value,
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 16,
          ),
        ),
      ),
    );
  }
}
