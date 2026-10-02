import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the chat page shows in place of the messages when its link names a
/// channel the account can't open (#2499), with a way to the default
/// channel.
///
/// Key prefixes: `chat_channel_not_found` on the pane and
/// `chat_channel_not_found_open_general` on its button.
class ChatChannelNotFound extends StatelessWidget {
  /// Creates the pane; [onOpenGeneral] goes to the default channel.
  const ChatChannelNotFound({required this.onOpenGeneral, super.key});

  /// Opens the default channel.
  final VoidCallback onOpenGeneral;

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      key: const ValueKey('chat_channel_not_found'),
      icon: QuarkIcons.forum_outlined,
      headline: 'Channel not found',
      subtext: Errors.chatChannelNotFound,
      action: FilledButton(
        key: const ValueKey('chat_channel_not_found_open_general'),
        onPressed: onOpenGeneral,
        child: const Text('Open #general'),
      ),
    );
  }
}
