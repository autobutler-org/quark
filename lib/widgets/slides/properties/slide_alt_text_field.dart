import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/properties/slide_commit_field.dart';

/// The alt text of the selected picture, what a screen reader reads for it
/// on the slide: a wrapping field that saves once editing ends — on Enter
/// or leaving the field — so a sentence is one undo step. While it has focus it keeps what is being typed; otherwise it
/// shows [value].
///
/// Key prefixes: `slide_prop_alt_text` on the field.
class SlideAltTextField extends StatelessWidget {
  /// A field showing [value].
  const SlideAltTextField({
    required this.value,
    required this.onSubmitted,
    this.readOnly = false,
    super.key,
  });

  /// The alt text the picture has.
  final String value;

  /// Saves the alt text.
  final ValueChanged<String> onSubmitted;

  /// Whether the field only shows the text, for a view-only presentation.
  final bool readOnly;

  @override
  Widget build(BuildContext context) => SlideCommitField(
    text: value,
    onCommit: (typed) {
      if (typed != value) onSubmitted(typed);
      return null;
    },
    builder: (context, controller, focusNode, commit) => TextField(
      key: const ValueKey('slide_prop_alt_text'),
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      minLines: 2,
      maxLines: 5,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Alt text',
        helperText: 'Describe the picture for people who cannot see it',
        helperMaxLines: 2,
      ),
      onSubmitted: (_) => commit(),
      onEditingComplete: commit,
    ),
  );
}
