import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A quiet line of explanation above a list: an info glyph and [text] in the
/// secondary color, padded to the page's gutter. It explains how the page
/// behaves (when things expire, where an action puts them) rather than
/// warning, so it has no card, border or tint.
///
/// Key prefixes: none of its own; the key the caller passes lands on the
/// note.
///
/// ```dart
/// const QuarkInfoNote(
///   text: 'Items here are deleted for good after 30 days.',
/// );
/// ```
class QuarkInfoNote extends StatelessWidget {
  /// Creates a note reading [text].
  const QuarkInfoNote({required this.text, super.key});

  /// The explanation, one or two sentences, wrapping as the width needs.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: tokens.spacingSm,
        children: [
          Icon(
            QuarkIcons.info_outline,
            size: 18,
            color: tokens.secondaryForeground,
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: tokens.secondaryForeground),
            ),
          ),
        ],
      ),
    );
  }
}
