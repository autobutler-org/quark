import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/properties/slide_commit_field.dart';

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
class SlideChartTitleField extends StatelessWidget {
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
  Widget build(BuildContext context) => SlideCommitField(
    text: value,
    onCommit: (typed) {
      final text = typed.trim();
      if (text != value) onSubmitted?.call(text);
      return null;
    },
    builder: (context, controller, focusNode, commit) => TextField(
      key: ValueKey(fieldKey),
      controller: controller,
      focusNode: focusNode,
      readOnly: onSubmitted == null,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Chart title',
        hintText: 'No title',
        isDense: dense,
      ),
      onSubmitted: (_) => commit(),
      onEditingComplete: commit,
    ),
  );
}
