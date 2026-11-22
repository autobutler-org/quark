import 'package:flutter/foundation.dart';

/// The side conversation branched from a message (#3561), as the message
/// draws it: how many replies it has and when the last one came.
///
/// A message with no replies has none. [hasUnread] stays false until the
/// caller tracks a side conversation's unread replies.
@immutable
class ChatBranchItem {
  /// Creates the summary of a side conversation with [replyCount] replies.
  const ChatBranchItem({
    required this.replyCount,
    required this.lastReplyAt,
    this.hasUnread = false,
  });

  /// How many replies the side conversation holds.
  final int replyCount;

  /// When the newest reply was sent.
  final DateTime lastReplyAt;

  /// Whether a reply came after the reader last looked.
  final bool hasUnread;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatBranchItem &&
          other.replyCount == replyCount &&
          other.lastReplyAt == lastReplyAt &&
          other.hasUnread == hasUnread;

  @override
  int get hashCode => Object.hash(replyCount, lastReplyAt, hasUnread);
}
