import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../../models/chat_branch_item.dart';
import '../../../theme/quark_tokens.dart';

/// The side conversation branched from a message (#3561), under the
/// message's body: "3 replies, last 2h ago" in the primary color, with a dot
/// before it while [ChatBranchItem.hasUnread].
///
/// A tap fires [onOpen], which opens the side conversation; null leaves the
/// chip inert. The chip is one 48dp-tall target.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefix: `message_branch_<messageId>` on the chip.
class ChatBranchChip extends StatelessWidget {
  /// Creates the chip for [branch] on message [messageId].
  const ChatBranchChip({
    required this.messageId,
    required this.branch,
    this.onOpen,
    super.key,
  });

  /// The id of the message the side conversation branches from.
  final String messageId;

  /// The side conversation's reply count and last reply.
  final ChatBranchItem branch;

  /// Opens the side conversation. Null leaves the chip inert.
  final VoidCallback? onOpen;

  /// What the chip reads for [branch] at [now]: the reply count, and how
  /// long ago the last reply came, in whole minutes, hours or days.
  static String labelFor(ChatBranchItem branch, DateTime now) {
    final count = branch.replyCount;
    final replies = count == 1 ? '1 reply' : '$count replies';
    final since = now.difference(branch.lastReplyAt);
    final last = since.inMinutes < 1
        ? 'just now'
        : since.inHours < 1
        ? '${since.inMinutes}m ago'
        : since.inDays < 1
        ? '${since.inHours}h ago'
        : '${since.inDays}d ago';
    return '$replies, last $last';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final label = labelFor(branch, DateTime.now());
    return Semantics(
      button: onOpen != null,
      label: branch.hasUnread ? 'Side conversation, new replies' : null,
      child: InkWell(
        key: ValueKey('message_branch_$messageId'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (branch.hasUnread) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: tokens.spacingXs),
              ],
              Icon(
                QuarkIcons.side_conversation,
                size: 16,
                color: tokens.primary,
              ),
              SizedBox(width: tokens.spacingXs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
