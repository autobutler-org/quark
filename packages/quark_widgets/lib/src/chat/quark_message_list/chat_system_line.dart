import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_message_item.dart';
import '../../theme/quark_tokens.dart';
import 'chat_message_row.dart';

/// A line the channel records about itself, such as a key rotation or someone
/// joining, drawn across the list with no author header.
///
/// An unverified line, one whose signature could not be checked, is drawn in
/// the warning color with a warning glyph and says so.
///
/// A part of `QuarkMessageList`, tested through it.
class ChatSystemLine extends StatelessWidget {
  /// Creates the line for [message].
  const ChatSystemLine({required this.message, super.key});

  /// The system message to draw.
  final ChatMessageItem message;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final color = message.isUnverified
        ? tokens.warning
        : tokens.secondaryForeground;
    final text = message.isUnverified
        ? '${message.body} (unverified)'
        : message.body;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingXs,
      ),
      child: Row(
        children: [
          Icon(
            message.isUnverified
                ? QuarkIcons.warning_amber
                : QuarkIcons.info_outline,
            size: 16,
            color: color,
          ),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
          SizedBox(width: tokens.spacingSm),
          Text(
            ChatMessageRow.timeOf(message.sentAt),
            style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
