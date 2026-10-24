import 'package:flutter/material.dart';

/// The state the slide editor's text fields share: a field that commits once
/// editing ends, on Enter or leaving it, so a value typed key by key is one
/// undo step. While it has focus it keeps what is being typed; otherwise it
/// shows [text], so a change elsewhere (a drag on the canvas, another
/// selection) updates it.
///
/// [builder] draws the `TextField` with the controller, focus node and the
/// commit to call from `onSubmitted`. Enter and the focus loss after it
/// commit once between them. [onCommit] gets the text typed and returns what
/// the field should show instead, such as the old value again for input it
/// refused, or null to keep what was typed.
///
/// Key prefixes: none of its own; [builder] keys the field.
class SlideCommitField extends StatefulWidget {
  /// A field showing [text], drawn by [builder].
  const SlideCommitField({
    required this.text,
    required this.onCommit,
    required this.builder,
    super.key,
  });

  /// What the field shows while it does not have focus.
  final String text;

  /// Takes the typed text when editing ends; returns the text to show
  /// instead, or null.
  final String? Function(String typed) onCommit;

  /// Draws the field with its [TextEditingController], [FocusNode] and the
  /// commit callback.
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    VoidCallback commit,
  )
  builder;

  @override
  State<SlideCommitField> createState() => _SlideCommitFieldState();
}

class _SlideCommitFieldState extends State<SlideCommitField> {
  late final _text = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  /// The text last committed, so Enter and the focus loss after it commit
  /// once between them.
  String? _committed;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(SlideCommitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.text != widget.text) {
      _text.text = widget.text;
      _committed = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final typed = _text.text;
    if (typed == _committed) return;
    _committed = typed;
    final shown = widget.onCommit(typed);
    if (shown != null) _text.text = shown;
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _text, _focus, _commit);
}
