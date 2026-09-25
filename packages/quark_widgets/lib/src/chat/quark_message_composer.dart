import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

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
/// Whether the user may write is the caller's: pass [disabledReason], such as
/// "You can read this channel but not write in it" or "Waiting for the key
/// to this channel", and the field is replaced by that sentence.
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
///   disabledReason: controller.canWrite ? null : readOnlyReason,
///   onSend: controller.send,
/// );
/// ```
class QuarkMessageComposer extends StatefulWidget {
  /// Creates a composer that hands what is written to [onSend].
  const QuarkMessageComposer({
    required this.onSend,
    this.hintText = 'Message',
    this.disabledReason,
    this.maxLines = 6,
    super.key,
  });

  /// Called with the trimmed text when the user sends a message that is not
  /// blank.
  final ValueChanged<String> onSend;

  /// The placeholder in the empty field.
  final String hintText;

  /// Why the user cannot write here, composed by the caller. Non-null shows
  /// this sentence in place of the field.
  final String? disabledReason;

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
    final reason = widget.disabledReason;

    if (reason != null) {
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
                reason,
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
