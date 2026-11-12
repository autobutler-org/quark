import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One outbound chat message the Quark has not stored yet.
///
/// While [error] is null the row shows that it is still sending. After a
/// failure it shows a failed indicator, in the warning color, and its own
/// Retry and Discard. It stays that way until the caller retries or discards
/// it. The message list does not draw these rows, so a send never looks
/// delivered before it is stored.
///
/// Key prefixes: `chat_send_sending_<id>` on the sending indicator,
/// `chat_send_failed_<id>` on the failed indicator,
/// `chat_failed_send_retry_<id>` and `chat_failed_send_discard_<id>` on the
/// buttons.
class ChatFailedSendBar extends StatelessWidget {
  /// Creates the row for outbound message [id], whose text is [text].
  ///
  /// [error] is the sentence shown once sending has failed. Leave it null
  /// while the send is still going out.
  const ChatFailedSendBar({
    required this.id,
    required this.text,
    required this.onRetry,
    required this.onDiscard,
    this.error,
    super.key,
  });

  /// The send's id, so this row's keys are not another send's.
  final String id;

  /// The message that is going out.
  final String text;

  /// Why it failed, already a sentence. Null while it is still sending.
  final String? error;

  /// Sends it again. Unused while [error] is null.
  final VoidCallback onRetry;

  /// Drops it. Unused while [error] is null.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final failed = error != null;
    final accent = failed ? tokens.warning : tokens.mutedForeground;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: failed ? tokens.warning.withValues(alpha: 0.12) : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingMd,
          vertical: tokens.spacingXs,
        ),
        child: Row(
          children: [
            if (failed)
              Icon(
                QuarkIcons.error_outline,
                key: ValueKey('chat_send_failed_$id'),
                size: 18,
                color: accent,
              )
            else
              QuarkLoader(key: ValueKey('chat_send_sending_$id'), size: 18),
            SizedBox(width: tokens.spacingSm),
            Expanded(
              child: Text(
                failed ? '$error "$text"' : 'Sending "$text"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent),
              ),
            ),
            if (failed) ...[
              TextButton(
                key: ValueKey('chat_failed_send_retry_$id'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              TextButton(
                key: ValueKey('chat_failed_send_discard_$id'),
                onPressed: onDiscard,
                child: const Text('Discard'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
