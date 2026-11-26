import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open side conversation (#4348) as a `QuarkBranchPanel`, fed from
/// [chat]: its parent, its replies as a `QuarkMessageList` that offers no
/// further branch, and a composer that replies with
/// [ChatController.sendInBranch], or edits a reply after
/// [ChatController.startEdit] put one there.
///
/// Replies that haven't sent wait above the composer with their own retry
/// and discard, as the channel's do. Copy, delete, react, links, edits and
/// closing are the page's, through the callbacks, so their confirmations
/// and errors read the same as in the channel. [composerEpoch] remounts the
/// composer, as the page does after a failed edit.
///
/// Keys: `chat_branch_messages_<rootId>` on the replies and
/// `chat_branch_composer_<rootId>_<editing id>_<epoch>` on the composer;
/// the rest are `QuarkBranchPanel`'s, `QuarkMessageList`'s and
/// `ChatFailedSendBar`'s.
class ChatBranchPane extends StatelessWidget {
  /// Creates the pane for [chat]'s open side conversation.
  const ChatBranchPane({
    required this.chat,
    required this.onClose,
    required this.onCopy,
    required this.onDelete,
    required this.onReact,
    required this.onSubmitEdit,
    required this.onOpenLink,
    required this.avatarBuilder,
    this.composerEpoch = 0,
    super.key,
  });

  /// The chat page's controller, with a side conversation open.
  final ChatController chat;

  /// Closes the side conversation.
  final VoidCallback onClose;

  /// Copies a reply's text, by id.
  final ValueChanged<String> onCopy;

  /// Deletes a reply, by id, after whatever confirmation the page asks.
  final ValueChanged<String> onDelete;

  /// Adds or takes back a reaction on a reply.
  final void Function(String messageId, String emoji) onReact;

  /// Saves the reply being edited as the text given.
  final ValueChanged<String> onSubmitEdit;

  /// Opens a link in a reply.
  final ValueChanged<Uri> onOpenLink;

  /// Builds an author's avatar, by account id.
  final Widget Function(BuildContext context, String userId) avatarBuilder;

  /// Bumped by the page to remount the composer.
  final int composerEpoch;

  @override
  Widget build(BuildContext context) {
    final c = chat;
    final rootId = c.branchId;
    final parent = c.branchParent;
    final editing = c.isEditingInBranch ? c.editingMessageId : null;
    final error = c.branchError;
    final permissions = c.selectedPermissions;
    return QuarkBranchPanel(
      parent: parent,
      onClose: onClose,
      parentAvatar: parent == null
          ? null
          : avatarBuilder(context, parent.authorId),
      messages: QuarkMessageList(
        key: ValueKey('chat_branch_messages_$rootId'),
        messages: c.branchItems,
        isBranch: true,
        isLoading: c.isLoadingBranch,
        error: error == null
            ? null
            : Errors.message(error, 'load the side conversation'),
        hasMore: c.hasOlderInBranch,
        onLoadOlder: c.loadOlderInBranch,
        permissions: permissions,
        currentUserId: c.currentUserKey,
        mentionNames: c.mentionNames,
        mentionEveryoneAuthorIds: c.mentionEveryoneAuthorIds,
        currentUserName: c.currentUserName,
        onCopy: onCopy,
        onEdit: c.startEdit,
        onDelete: onDelete,
        onReact: onReact,
        onOpenLink: onOpenLink,
        avatarBuilder: avatarBuilder,
      ),
      composer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final send in c.branchOutboundSends)
            ChatFailedSendBar(
              id: send.id,
              text: send.text,
              error: send.failed
                  ? Errors.message(send.error, 'send the message')
                  : null,
              onRetry: () => c.retry(send.id),
              onDiscard: () => c.discard(send.id),
            ),
          if (editing != null)
            QuarkComposerContextBar(
              icon: QuarkIcons.edit_outlined,
              title: 'Editing message',
              text: c.editingText,
              cancelTooltip: 'Stop editing',
              onCancel: c.cancelEdit,
            ),
          QuarkEdgeInset(
            child: QuarkMessageComposer(
              key: ValueKey(
                'chat_branch_composer_${rootId}_${editing ?? ''}_'
                '$composerEpoch',
              ),
              initialText: editing != null ? c.editingText : '',
              hintText: editing != null ? 'Edit message' : 'Reply',
              // Editing is authorship, not send_messages (#2426).
              permissions: editing != null
                  ? {...permissions, ChatPermission.sendMessages}
                  : permissions,
              isWaitingForKey: c.isWaitingForKey,
              maxLength: ChatConfig.maxMessageLength,
              mentionNames: c.mentionNames,
              onSend: editing != null ? onSubmitEdit : c.sendInBranch,
            ),
          ),
        ],
      ),
    );
  }
}
