import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_message_item.dart';
import '../../theme/quark_tokens.dart';

/// One message a person sent, with the author's avatar, name and time above
/// it when it starts a group, or indented under the group's header when it
/// does not.
///
/// Draws the body of a text message, the "waiting for key" placeholder, or a
/// deleted message's tombstone, according to [ChatMessageItem.kind]. System
/// lines are a `ChatSystemLine` instead.
///
/// A part of `QuarkMessageList`, tested through it.
class ChatMessageRow extends StatelessWidget {
  /// Creates the row for [message].
  const ChatMessageRow({
    required this.message,
    required this.avatar,
    this.avatarSize = 32,
    super.key,
  });

  /// The message to draw.
  final ChatMessageItem message;

  /// The author's avatar, which also means this row starts a group and shows
  /// the author's name and the time. Null indents the row under the group
  /// above it.
  final Widget? avatar;

  /// The width reserved for the avatar, so grouped rows line up under it.
  final double avatarSize;

  /// The time drawn beside the author's name, as `HH:mm`.
  static String timeOf(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final avatar = this.avatar;
    final muted = TextStyle(
      color: tokens.mutedForeground,
      fontStyle: FontStyle.italic,
    );

    final body = switch (message.kind) {
      ChatMessageKind.waitingForKey => Row(
        children: [
          Icon(
            QuarkIcons.key_outlined,
            size: 16,
            color: tokens.mutedForeground,
          ),
          SizedBox(width: tokens.spacingXs),
          Flexible(
            child: Text(
              'Waiting for the key to read this message',
              style: muted,
            ),
          ),
        ],
      ),
      ChatMessageKind.deleted => Row(
        children: [
          Icon(
            QuarkIcons.delete_outline,
            size: 16,
            color: tokens.mutedForeground,
          ),
          SizedBox(width: tokens.spacingXs),
          Flexible(child: Text('This message was deleted', style: muted)),
        ],
      ),
      ChatMessageKind.text || ChatMessageKind.system => Text(
        message.body,
        style: TextStyle(
          color: message.isUnverified ? tokens.warning : tokens.foreground,
        ),
      ),
    };

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: tokens.spacingMd,
        top: avatar == null ? tokens.spacingXs : tokens.spacingSm,
        end: tokens.spacingMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: avatarSize, child: avatar),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (avatar != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          message.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: tokens.spacingSm),
                      Text(
                        timeOf(message.sentAt),
                        style: TextStyle(
                          color: tokens.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                body,
                if (message.isUnverified)
                  Row(
                    children: [
                      Icon(
                        QuarkIcons.warning_amber,
                        size: 14,
                        color: tokens.warning,
                      ),
                      SizedBox(width: tokens.spacingXs),
                      Flexible(
                        child: Text(
                          'Unverified',
                          style: TextStyle(color: tokens.warning, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
