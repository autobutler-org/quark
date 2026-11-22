import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_avatar.dart';
import '../layout/quark_bar_icon_button.dart';
import '../layout/quark_sheet.dart';
import '../models/chat_message_item.dart';
import '../theme/quark_tokens.dart';
import 'quark_message_list.dart';
import 'quark_message_list/chat_message_row.dart';
import 'quark_message_list/chat_message_row/chat_message_quote.dart';

/// A side conversation (#3561) beside its channel: a header named for the
/// message it branches from, that message, then the caller's replies and
/// composer.
///
/// The header reads [titleFor] the [parent], one line cut short however
/// long it is, with a close button that fires [onClose]. Inside a
/// [QuarkSheet], which has a title and a close button of its own, the panel
/// leaves its header to the sheet: `QuarkChatLayout` puts it in one on a
/// narrow window.
///
/// Under the header the [parent] is drawn as the channel draws it, with no
/// actions, scrolling by itself when it is long. A parent that is null,
/// deleted or still waiting for its key reads "Original message
/// unavailable" instead; its replies stay readable. Then [messages], given
/// the rest of the height, and [composer] at the foot. Usually a
/// `QuarkMessageList` with `isBranch` set, so it offers no further branch,
/// and a `QuarkMessageComposer`. Loading, errors and sending are theirs.
///
/// Nothing animates.
///
/// Key prefixes: `branch_panel_title` on the header's title,
/// `branch_panel_close` on its close button, `branch_panel_parent` on the
/// parent's area, and `branch_panel_parent_unavailable` on the line read in
/// place of a parent that can't be shown.
///
/// ```dart
/// QuarkBranchPanel(
///   parent: controller.branchParent,
///   onClose: controller.closeBranch,
///   messages: QuarkMessageList(
///     messages: controller.branchItems,
///     isBranch: true,
///   ),
///   composer: QuarkMessageComposer(onSend: controller.sendInBranch),
/// );
/// ```
class QuarkBranchPanel extends StatelessWidget {
  /// Creates the side conversation branched from [parent].
  const QuarkBranchPanel({
    required this.parent,
    required this.messages,
    required this.onClose,
    this.composer,
    this.parentAvatar,
    super.key,
  });

  /// The title of a side conversation whose parent has no line to show.
  static const String fallbackTitle = 'Side conversation';

  /// The message the side conversation branches from. Null when it isn't
  /// loaded or can't be read.
  final ChatMessageItem? parent;

  /// The replies, given the height under the parent.
  final Widget messages;

  /// What writes a reply, at the foot. Null leaves the foot empty.
  final Widget? composer;

  /// Fires when the header's close button is tapped.
  final VoidCallback onClose;

  /// The parent author's avatar, [QuarkMessageList.avatarSize] across. Null
  /// draws a [QuarkAvatar] with their initials.
  final Widget? parentAvatar;

  /// Whether [parent] can be drawn: it is there, not deleted, and its key
  /// has arrived.
  static bool isAvailable(ChatMessageItem? parent) =>
      parent != null &&
      parent.kind != ChatMessageKind.deleted &&
      parent.kind != ChatMessageKind.waitingForKey;

  /// What a side conversation branched from [parent] is called: the
  /// parent's first line that isn't blank, or [fallbackTitle].
  static String titleFor(ChatMessageItem? parent) {
    if (parent == null || !isAvailable(parent)) return fallbackTitle;
    for (final line in parent.body.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return fallbackTitle;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final parent = this.parent;
    final composer = this.composer;
    final inSheet = context.findAncestorWidgetOfExactType<QuarkSheet>() != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inSheet) ...[
          Padding(
            // Less the margin around the button's 48dp touch target, as the
            // chat layout's header does.
            padding: EdgeInsets.all(
              tokens.spacingSm - QuarkBarIconButton.tapTargetMargin,
            ),
            child: Row(
              children: [
                SizedBox(width: tokens.spacingSm),
                Expanded(
                  child: Text(
                    titleFor(parent),
                    key: const ValueKey('branch_panel_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacingSm),
                QuarkBarIconButton(
                  key: const ValueKey('branch_panel_close'),
                  icon: QuarkIcons.close,
                  tooltip: 'Close side conversation',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
        ],
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('branch_panel_parent'),
            padding: EdgeInsets.only(bottom: tokens.spacingSm),
            child: parent != null && isAvailable(parent)
                ? ChatMessageRow(
                    message: parent,
                    avatarSize: QuarkMessageList.avatarSize,
                    avatar:
                        parentAvatar ??
                        QuarkAvatar(
                          id: parent.authorId,
                          name: parent.authorName,
                          size: QuarkMessageList.avatarSize,
                        ),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      tokens.spacingMd,
                      tokens.spacingSm,
                      tokens.spacingMd,
                      0,
                    ),
                    child: Text(
                      ChatMessageQuote.unavailableText,
                      key: const ValueKey('branch_panel_parent_unavailable'),
                      style: TextStyle(
                        color: tokens.mutedForeground,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
        ),
        Divider(height: 1, color: tokens.border),
        // The replies get twice what the parent may take.
        Expanded(flex: 2, child: messages),
        ?composer,
      ],
    );
  }
}
