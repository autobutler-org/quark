import 'package:flutter/material.dart';

/// The selected chart's title: a one-line field that saves once editing
/// ends — on Enter or leaving the field — so a title is one undo step.
/// While it has focus it keeps what is being typed; otherwise it shows
/// [value]. A null [onSubmitted] — a view-only presentation — shows the
/// title in a field that takes no input.
///
/// [dense] draws it compact, for the toolbar row; the properties panel
/// uses the full size.
///
/// Key prefixes: `slide_chart_title` in the toolbar,
/// `slide_prop_chart_title` in the properties panel (set by [fieldKey]).
class SlideChartTitleField extends StatefulWidget {
  /// A field showing [value], keyed [fieldKey].
  const SlideChartTitleField({
    required this.value,
    required this.onSubmitted,
    required this.fieldKey,
    this.dense = false,
    super.key,
  });

  /// The title the chart has; empty for none.
  final String value;

  /// Saves the title; null takes no input.
  final ValueChanged<String>? onSubmitted;

  /// The text field's `ValueKey` name.
  final String fieldKey;

  /// Whether it is drawn compact, for the toolbar row.
  final bool dense;

  @override
  State<SlideChartTitleField> createState() => _SlideChartTitleFieldState();
}

class _SlideChartTitleFieldState extends State<SlideChartTitleField> {
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
  void didUpdateWidget(SlideChartTitleField oldWidget) {
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
    final onSubmitted = widget.onSubmitted;
    final text = _text.text.trim();
    if (onSubmitted == null || text == widget.value || text == _submitted) {
      return;
    }
    _submitted = text;
    onSubmitted(text);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: ValueKey(widget.fieldKey),
    controller: _text,
    focusNode: _focus,
    readOnly: widget.onSubmitted == null,
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(
      labelText: 'Chart title',
      hintText: 'No title',
      isDense: widget.dense,
    ),
    onSubmitted: (_) => _submit(),
    onEditingComplete: _submit,
  );
}
