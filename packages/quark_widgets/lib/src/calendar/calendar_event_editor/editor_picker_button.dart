import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// A field-shaped button showing a date or a time, which opens a picker in
/// `CalendarEventEditor`. It draws a two-pixel error border when [invalid].
class EditorPickerButton extends StatelessWidget {
  /// Creates a button showing [value].
  const EditorPickerButton({
    required this.value,
    required this.semanticLabel,
    required this.onPressed,
    this.invalid = false,
    super.key,
  });

  /// The date or time on show, already worded.
  final String value;

  /// What the field is, for a screen reader: "Start date".
  final String semanticLabel;

  /// Opens the picker.
  final VoidCallback? onPressed;

  /// Whether the value breaks a rule, drawn as an error border.
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusMd);
    return Semantics(
      button: true,
      label: '$semanticLabel, $value',
      excludeSemantics: true,
      child: Material(
        color: tokens.input,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: invalid
              ? BorderSide(color: tokens.error, width: 2)
              : BorderSide(color: tokens.border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: tokens.foreground),
                    ),
                  ),
                  Icon(
                    QuarkIcons.expand_more_rounded,
                    size: 16,
                    color: tokens.secondaryForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
