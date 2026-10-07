import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// One thing that happens when remote access is turned off: a colored
/// [icon] and a sentence, as `RemoteAccessTurnOffDialog` lists them.
class RemoteAccessTurnOffConsequence extends StatelessWidget {
  /// Creates the line.
  const RemoteAccessTurnOffConsequence({
    required this.icon,
    required this.color,
    required this.text,
    super.key,
  });

  /// The glyph before the sentence.
  final IconData icon;

  /// The glyph's color, which says whether this is a loss or a reassurance.
  final Color color;

  /// The consequence, in a sentence.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: color),
        ),
        Expanded(child: Text(text)),
      ],
    );
  }
}
