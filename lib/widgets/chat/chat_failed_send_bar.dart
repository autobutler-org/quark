import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The row above the chat composer when a message didn't send, offering to
/// send it again or drop it.
///
/// `QuarkMessageList` has no failed state for a row, so the message stays in
/// the list as written and this row says it didn't go.
///
/// Key prefixes: `chat_failed_send_retry` and `chat_failed_send_discard` on
/// the buttons.
class ChatFailedSendBar extends StatelessWidget {
  /// Creates the row for a message reading [text].
  const ChatFailedSendBar({
    required this.text,
    required this.error,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  /// The message that didn't send.
  final String text;

  /// Why, already a sentence.
  final String error;

  /// Sends it again.
  final VoidCallback onRetry;

  /// Drops it.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingXs,
      ),
      child: Row(
        children: [
          Icon(QuarkIcons.error_outline, size: 18, color: tokens.warning),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Text(
              '$error "$text"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.warning),
            ),
          ),
          TextButton(
            key: const ValueKey('chat_failed_send_retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
          TextButton(
            key: const ValueKey('chat_failed_send_discard'),
            onPressed: onDiscard,
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
