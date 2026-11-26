import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open channel's side conversations (#4351) as a `QuarkBranchList`,
/// fed from [chat] and kept current as it changes: the quiet ones, whose
/// last reply is older than [ChatConfig.quietBranchAfter], folded under
/// Quiet. Choosing one fires [onOpen] with its message id.
///
/// Keys are `QuarkBranchList`'s.
class ChatBranchListSheet extends StatelessWidget {
  /// Creates the list for [chat]'s open channel.
  const ChatBranchListSheet({
    required this.chat,
    required this.onOpen,
    super.key,
  });

  /// The chat page's controller.
  final ChatController chat;

  /// Opens the side conversation of the message id given.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat,
    builder: (context, _) {
      final error = chat.branchListError;
      return QuarkBranchList(
        branches: chat.branchListItems,
        quietBefore: DateTime.now().subtract(ChatConfig.quietBranchAfter),
        isQuietExpanded: chat.isQuietBranchesExpanded,
        onQuietExpandedChanged: chat.setQuietBranchesExpanded,
        isLoading: chat.isLoadingBranchList,
        error: error == null
            ? null
            : Errors.message(error, 'load the side conversations'),
        hasMore: chat.hasMoreBranchList,
        onLoadMore: () => chat.loadBranchList(more: true),
        onOpen: onOpen,
      );
    },
  );
}
