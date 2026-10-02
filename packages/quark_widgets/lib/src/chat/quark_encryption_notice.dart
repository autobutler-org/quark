import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/chat_encryption_status.dart';
import '../theme/quark_tokens.dart';

/// A card above a channel's composer saying where its encryption stands and
/// what the user can do about it, so a channel mid-way through a key step
/// reads as a step rather than as broken.
///
/// Each [ChatEncryptionStatus] has its own title ([titleOf]) and a body
/// ([bodyOf]) that leads with the next step in plain words. A
/// [ChatEncryptionStatus.waitingForKey] notice is drawn in the primary color,
/// since it blocks sending; the others in the warning color.
///
/// [onCheckAgain], offered only while waiting for a key, asks the caller to
/// look for the key now; [isChecking] holds it still with a loader.
/// [onLearnMore] asks the caller to explain encryption, usually with a
/// `QuarkEncryptionHelpDialog`. Without a callback, its button is left out.
///
/// Key prefixes: `encryption_notice` on the card,
/// `encryption_notice_check_again` and `encryption_notice_learn_more` on its
/// buttons.
///
/// ```dart
/// QuarkEncryptionNotice(
///   status: ChatEncryptionStatus.waitingForKey,
///   isChecking: controller.isCheckingKey,
///   onCheckAgain: controller.checkKey,
///   onLearnMore: showEncryptionHelp,
/// );
/// ```
class QuarkEncryptionNotice extends StatelessWidget {
  /// Creates the notice for [status].
  const QuarkEncryptionNotice({
    required this.status,
    this.onCheckAgain,
    this.isChecking = false,
    this.onLearnMore,
    super.key,
  });

  /// Where the channel's encryption stands.
  final ChatEncryptionStatus status;

  /// Called when "Check again" is tapped. Only offered for
  /// [ChatEncryptionStatus.waitingForKey].
  final VoidCallback? onCheckAgain;

  /// Whether a check is running. Holds "Check again" still with a loader.
  final bool isChecking;

  /// Called when "What does this mean?" is tapped.
  final VoidCallback? onLearnMore;

  /// The notice's heading for [status].
  static String titleOf(ChatEncryptionStatus status) => switch (status) {
    ChatEncryptionStatus.waitingForKey => 'Waiting for the key to this channel',
    ChatEncryptionStatus.unverifiedKey => "This channel's key isn't verified",
    ChatEncryptionStatus.unreadableHistory =>
      'Some earlier messages are hidden',
  };

  /// The notice's explanation for [status], next step first.
  static String bodyOf(ChatEncryptionStatus status) => switch (status) {
    ChatEncryptionStatus.waitingForKey =>
      'Nothing is wrong. A member shares the key with you automatically the '
          'next time they open Quark, and this channel opens on its own. '
          'To speed it up, ask someone in the channel to open Chat.',
    ChatEncryptionStatus.unverifiedKey =>
      'Messages still send and arrive. Quark couldn\'t confirm who made the '
          'newest key. If no one in the channel expected a change, tell an '
          'admin.',
    ChatEncryptionStatus.unreadableHistory =>
      'They were sent with a key you were never given, such as before you '
          'joined. New messages are not affected, and there is nothing you '
          'need to do.',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final waiting = status == ChatEncryptionStatus.waitingForKey;
    final color = waiting ? tokens.primary : tokens.warning;
    final onCheckAgain = waiting ? this.onCheckAgain : null;
    final onLearnMore = this.onLearnMore;

    return Padding(
      key: const ValueKey('encryption_notice'),
      padding: EdgeInsets.fromLTRB(
        tokens.spacingSm,
        tokens.spacingSm,
        tokens.spacingSm,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (status) {
                  ChatEncryptionStatus.waitingForKey => QuarkIcons.key_rounded,
                  ChatEncryptionStatus.unverifiedKey =>
                    QuarkIcons.warning_amber,
                  ChatEncryptionStatus.unreadableHistory =>
                    QuarkIcons.lock_outline,
                },
                size: 20,
                color: color,
              ),
              SizedBox(width: tokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleOf(status),
                      style: TextStyle(
                        color: tokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.spacingXs),
                    Text(
                      bodyOf(status),
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                    if (onCheckAgain != null || onLearnMore != null)
                      Wrap(
                        spacing: tokens.spacingSm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (onCheckAgain != null)
                            TextButton.icon(
                              key: const ValueKey(
                                'encryption_notice_check_again',
                              ),
                              onPressed: isChecking ? null : onCheckAgain,
                              icon: isChecking
                                  ? const QuarkLoader(size: 16)
                                  : const Icon(QuarkIcons.refresh, size: 18),
                              label: const Text('Check again'),
                            ),
                          if (onLearnMore != null)
                            TextButton.icon(
                              key: const ValueKey(
                                'encryption_notice_learn_more',
                              ),
                              onPressed: onLearnMore,
                              icon: const Icon(
                                QuarkIcons.help_outline,
                                size: 18,
                              ),
                              label: const Text('What does this mean?'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
