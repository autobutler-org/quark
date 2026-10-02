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
    this.maxLength,
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

  /// The longest message that sends, in UTF-16 code units as
  /// [String.length] counts them, measured on the trimmed text. Null has no
  /// limit.
  ///
  /// Within a tenth of it, a counter under the field says how much is left,
  /// key `message_composer_counter`. Past it, the counter gives way to
  /// [overLimitText], key `message_composer_too_long`, the send button turns
  /// off with [tooLongText] as its tooltip, and Enter keeps the draft rather
  /// than sending it.
  final int? maxLength;

  /// Said when Enter is pressed on a blank message, under the field with key
  /// `message_composer_hint`, and as the turned-off send button's tooltip.
  static const String blankHint = 'Type a message to send';

  /// The send button's tooltip when the message is longer than [maxLength].
  static const String tooLongText = 'This message is too long to send';

  /// Said under the field when the message is [count] code units longer than
  /// [maxLength].
  static String overLimitText(int count) =>
      '$count characters over the limit. Shorten it to send.';

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

  /// Whether Enter was pressed on a blank message; typing anything clears it.
  bool _showBlankHint = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_clearBlankHint);
  }

  void _clearBlankHint() {
    if (_showBlankHint && _text.text.trim().isNotEmpty) {
      setState(() => _showBlankHint = false);
    }
  }

  /// How many code units the trimmed text is over [maxLength], negative
  /// when under, and null with no limit.
  int? _overBy(String message) {
    final max = widget.maxLength;
    return max == null ? null : message.length - max;
  }

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
    if (message.isEmpty) {
      // Enter on a blank message used to do nothing at all (#2502).
      setState(() => _showBlankHint = true);
      return;
    }
    if ((_overBy(message) ?? 0) > 0) return;
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

    final field = ListenableBuilder(
      listenable: _text,
      builder: (context, _) {
        final overBy = _overBy(_text.text.trim());
        final max = widget.maxLength;
        // One line under the field: on a phone, an error beside a counter
        // squeezes the error into a column a word wide.
        final over = overBy != null && overBy > 0;
        final counter = over || max == null || -overBy! > max ~/ 10
            ? null
            : '${-overBy} characters left';
        return TextField(
          key: const ValueKey('message_composer_field'),
          controller: _text,
          focusNode: _focus,
          minLines: 1,
          maxLines: widget.maxLines,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: widget.hintText,
            helper: _showBlankHint
                ? const Text(
                    QuarkMessageComposer.blankHint,
                    key: ValueKey('message_composer_hint'),
                  )
                : null,
            error: over
                ? Text(
                    QuarkMessageComposer.overLimitText(overBy),
                    key: const ValueKey('message_composer_too_long'),
                  )
                : null,
            counter: counter == null
                ? null
                : Text(
                    counter,
                    key: const ValueKey('message_composer_counter'),
                  ),
          ),
        );
      },
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
            builder: (context, _) {
              final message = _text.text.trim();
              final reason = message.isEmpty
                  ? QuarkMessageComposer.blankHint
                  : (_overBy(message) ?? 0) > 0
                  ? QuarkMessageComposer.tooLongText
                  : null;
              return IconButton.filled(
                key: const ValueKey('message_composer_send'),
                tooltip: reason ?? 'Send',
                icon: const Icon(QuarkIcons.send_rounded),
                onPressed: reason == null ? _send : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
