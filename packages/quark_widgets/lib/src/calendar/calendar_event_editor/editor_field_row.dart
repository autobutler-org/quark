import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// One labeled field of `CalendarEventEditor`: the label beside the field on a
/// wide form, above it on a narrow one.
class EditorFieldRow extends StatelessWidget {
  /// Creates a row labeled [label] around [child].
  const EditorFieldRow({
    required this.label,
    required this.wide,
    required this.child,
    this.icon,
    this.alignTop = false,
    super.key,
  });

  /// The field's name.
  final String label;

  /// A glyph before the label, from `QuarkIcons`.
  final IconData? icon;

  /// Whether the form is wide enough to put the label beside the field.
  final bool wide;

  /// Whether a wide label aligns with the field's first line rather than its
  /// middle, for fields taller than one line.
  final bool alignTop;

  /// The field.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (icon != null)
          Icon(icon, size: wide ? 16 : 14, color: tokens.secondaryForeground),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: wide ? 13 : 12,
              fontWeight: wide ? FontWeight.w400 : FontWeight.w500,
              color: tokens.secondaryForeground,
            ),
          ),
        ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [text, child],
      );
    }
    return Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      spacing: 12,
      children: [
        SizedBox(
          width: 104,
          child: Padding(
            padding: EdgeInsets.only(top: alignTop ? 9 : 0),
            child: text,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
