import 'package:flutter/material.dart';

import '../../models/quark_help_topic.dart';
import '../../theme/quark_tokens.dart';

/// One [QuarkHelpTopic] in a `QuarkHelpDialog`: its optional glyph, its bold
/// heading, and its paragraph wrapped beneath.
///
/// Key prefixes: none of its own; the dialog keys each row
/// `quark_help_topic_<index>`.
///
/// ```dart
/// QuarkHelpTopicRow(
///   key: const ValueKey('quark_help_topic_0'),
///   topic: topic,
/// );
/// ```
class QuarkHelpTopicRow extends StatelessWidget {
  /// Creates the row for [topic].
  const QuarkHelpTopicRow({required this.topic, super.key});

  /// The topic this row shows.
  final QuarkHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final icon = topic.icon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        if (icon != null) Icon(icon, size: 20, color: tokens.primary),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: tokens.spacingXs,
            children: [
              Text(
                topic.heading,
                style: TextStyle(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(topic.body, style: TextStyle(color: tokens.mutedForeground)),
            ],
          ),
        ),
      ],
    );
  }
}
