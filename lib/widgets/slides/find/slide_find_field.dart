import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A text field of the slide find bar: the query or the replacement, named
/// by [label] — shown inside it while it is empty and read by a screen
/// reader — at least 48 pixels tall.
///
/// Enter runs [onSubmitted] and keeps the cursor in the field, so pressing
/// it again steps on through the matches.
///
/// Key prefixes: none of its own; the bar keys each field.
class SlideFindField extends StatelessWidget {
  /// Creates a field editing [controller].
  const SlideFindField({
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.onSubmitted,
    super.key,
  });

  /// The field's text.
  final TextEditingController controller;

  /// What the field is for: "Find" or "Replace with".
  final String label;

  /// The glyph before the text.
  final IconData icon;

  /// The field's focus, or null for its own.
  final FocusNode? focusNode;

  /// Runs when Enter is pressed.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: tokens.border),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      // Keeps focus after Enter, which would otherwise end editing.
      onEditingComplete: () {},
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: Icon(icon, size: 18),
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        isDense: true,
        filled: true,
        fillColor: tokens.input,
        border: border,
        enabledBorder: border,
      ),
    );
  }
}
