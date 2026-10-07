import 'package:flutter/material.dart';

/// The alt text of the selected picture, what a screen reader reads for it
/// on the slide: a wrapping field that saves once editing ends — on Enter
/// or leaving the field — so a sentence is one undo step. While it has focus it keeps what is being typed; otherwise it
/// shows [value].
///
/// Key prefixes: `slide_prop_alt_text` on the field.
class SlideAltTextField extends StatefulWidget {
  /// A field showing [value].
  const SlideAltTextField({
    required this.value,
    required this.onSubmitted,
    super.key,
  });

  /// The alt text the picture has.
  final String value;

  /// Saves the alt text.
  final ValueChanged<String> onSubmitted;

  @override
  State<SlideAltTextField> createState() => _SlideAltTextFieldState();
}

class _SlideAltTextFieldState extends State<SlideAltTextField> {
  late final _text = TextEditingController(text: widget.value);
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
  void didUpdateWidget(SlideAltTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _text.text = widget.value;
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
    if (_text.text == widget.value || _text.text == _submitted) return;
    _submitted = _text.text;
    widget.onSubmitted(_text.text);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('slide_prop_alt_text'),
    controller: _text,
    focusNode: _focus,
    minLines: 2,
    maxLines: 5,
    keyboardType: TextInputType.text,
    textInputAction: TextInputAction.done,
    decoration: const InputDecoration(
      labelText: 'Alt text',
      helperText: 'Describe the picture for people who cannot see it',
      helperMaxLines: 2,
    ),
    onSubmitted: (_) => _submit(),
    onEditingComplete: _submit,
  );
}
