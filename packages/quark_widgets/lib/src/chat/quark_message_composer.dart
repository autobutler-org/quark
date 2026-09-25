import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/chat_permission.dart';
import '../theme/quark_tokens.dart';

/// The field under a message list where a message is written and sent.
///
/// The field grows with what is typed, up to [maxLines], then scrolls. On a
/// desktop, including a desktop browser, Enter sends and Shift+Enter starts a new line; on a
/// phone, Enter starts a new line and the send button sends. The send button
/// is there on every platform. Enter never sends while an input method is
/// still composing, since that Enter confirms the composition. What is sent is trimmed, a blank message is
/// never sent, and the field clears once [onSend] has been called.
///
/// The field is replaced by a sentence saying why the user can't write, for
/// two reasons of the channel's own and one of the caller's, first match
/// wins:
///
/// - [permissions] lacks [ChatPermission.readMessages]: [notMemberReason],
///   for someone who manages the channel without being in the conversation.
/// - [permissions] lacks [ChatPermission.sendMessages]: [noSendReason], which
///   lasts until someone changes the user's permissions.
/// - [isWaitingForKey]: [waitingForKeyReason], which resolves itself once a
///   member shares the channel key.
/// - [disabledReason], any other sentence the caller composes.
///
/// The text controller and focus node are [State] because Flutter needs them
/// to live across rebuilds; the outcome leaves through [onSend].
///
/// Key prefixes: `message_composer_field` on the text field,
/// `message_composer_send` on the send button, and
/// `message_composer_disabled` on the disabled sentence.
///
/// ```dart
/// QuarkMessageComposer(
///   hintText: 'Message #general',
///   permissions: controller.selectedPermissions,
///   isWaitingForKey: controller.isWaitingForKey,
///   onSend: controller.send,
/// );
/// ```
class QuarkMessageComposer extends StatefulWidget {
  /// Creates a composer that hands what is written to [onSend].
  const QuarkMessageComposer({
    required this.onSend,
    this.hintText = 'Message',
    this.permissions,
    this.isWaitingForKey = false,
    this.disabledReason,
    this.maxLines = 6,
    super.key,
  });

  /// Called with the trimmed text when the user sends a message that is not
  /// blank.
  final ValueChanged<String> onSend;

  /// The placeholder in the empty field.
  final String hintText;

  /// What the user may do in the channel. Without
  /// [ChatPermission.sendMessages] the field is replaced by [noSendReason].
  /// Null doesn't check.
  final Set<ChatPermission>? permissions;

  /// Whether the user is waiting for a member to share the channel key, which
  /// replaces the field with [waitingForKeyReason].
  final bool isWaitingForKey;

  /// Any other reason the user cannot write here, composed by the caller.
  /// Non-null shows this sentence in place of the field.
  final String? disabledReason;

  /// Shown to a user without [ChatPermission.readMessages].
  static const String notMemberReason =
      'You are not a member of this conversation';

  /// Shown to a user without [ChatPermission.sendMessages].
  static const String noSendReason =
      'You can read this channel but not send messages in it';

  /// Shown while the user waits for the channel key.
  static const String waitingForKeyReason =
      'Waiting for a member to share the key to this channel';

  /// How many lines the field grows to before it scrolls.
  final int maxLines;

  /// Whether Enter sends on the current platform: on a desktop, not on a
  /// phone, where the keyboard's return key has to start new lines. On the
  /// web [defaultTargetPlatform] reports the browser's OS, so a phone browser
  /// counts as a phone.
  static bool enterSends() => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  @override
  State<QuarkMessageComposer> createState() => _QuarkMessageComposerState();
}

class _QuarkMessageComposerState extends State<QuarkMessageComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sendFromEnter() {
    // An input method (Japanese, Chinese, Korean) uses Enter to confirm what
    // it is composing; that Enter is not a send. The send button still sends,
    // since a phone keyboard keeps a composing region while plain typing.
    if (_text.value.composing.isValid) return;
    _send();
  }

  void _send() {
    final message = _text.text.trim();
    if (message.isEmpty) return;
    widget.onSend(message);
    _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final permissions = widget.permissions;
    final reason = permissions == null
        ? null
        : !permissions.contains(ChatPermission.readMessages)
        ? QuarkMessageComposer.notMemberReason
        : !permissions.contains(ChatPermission.sendMessages)
        ? QuarkMessageComposer.noSendReason
        : null;
    final shown =
        reason ??
        (widget.isWaitingForKey
            ? QuarkMessageComposer.waitingForKeyReason
            : widget.disabledReason);

    if (shown != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Row(
          key: const ValueKey('message_composer_disabled'),
          children: [
            Icon(
              QuarkIcons.lock_outline,
              size: 18,
              color: tokens.mutedForeground,
            ),
            SizedBox(width: tokens.spacingSm),
            Expanded(
              child: Text(
                shown,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ),
          ],
        ),
      );
    }

    final field = TextField(
      key: const ValueKey('message_composer_field'),
      controller: _text,
      focusNode: _focus,
      minLines: 1,
      maxLines: widget.maxLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(hintText: widget.hintText),
    );

    return Padding(
      padding: EdgeInsets.all(tokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: QuarkMessageComposer.enterSends()
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _sendFromEnter,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          _sendFromEnter,
                    },
                    child: field,
                  )
                : field,
          ),
          SizedBox(width: tokens.spacingSm),
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => IconButton.filled(
              key: const ValueKey('message_composer_send'),
              tooltip: 'Send',
              icon: const Icon(QuarkIcons.send_rounded),
              onPressed: _text.text.trim().isEmpty ? null : _send,
            ),
          ),
        ],
      ),
    );
  }
}
