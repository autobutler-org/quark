import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_message_item.dart';
import '../../theme/quark_tokens.dart';
import '../quark_branch_panel.dart';
import '../quark_message_list/chat_message_row/chat_branch_chip.dart';
import '../quark_message_list/chat_message_row/chat_message_quote.dart';

/// One side conversation in a `QuarkBranchList`: [message]'s first line, or
/// "Original message unavailable" when it is deleted or waiting for its key,
/// in bold while its branch has unread replies, over its author and "3
/// replies, last 2h ago" at [now]. A tap fires [onTap].
///
/// A part of `QuarkBranchList`, tested through it. Its key is the list's
/// `branch_row_<messageId>`.
class BranchListRow extends StatelessWidget {
  /// Creates the row for [message].
  const BranchListRow({
    required this.message,
    required this.now,
    required this.onTap,
    super.key,
  });

  /// The message the side conversation branches from, with its branch.
  final ChatMessageItem message;

  /// The time "last 2h ago" counts from.
  final DateTime now;

  /// Opens the side conversation.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final available = QuarkBranchPanel.isAvailable(message);
    final branch = message.branch;
    return ListTile(
      leading: Icon(QuarkIcons.side_conversation, color: tokens.primary),
      title: Text(
        available
            ? QuarkBranchPanel.titleFor(message)
            : ChatMessageQuote.unavailableText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: available ? tokens.foreground : tokens.mutedForeground,
          fontStyle: available ? null : FontStyle.italic,
          fontWeight: (branch?.hasUnread ?? false) ? FontWeight.w700 : null,
        ),
      ),
      subtitle: Text(
        [
          message.authorName,
          if (branch != null) ChatBranchChip.labelFor(branch, now),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      onTap: onTap,
    );
  }
}
