import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the chat page shows in place of chat while it is locked: on web after
/// a reload, when the keys that open messages live only in memory (#2416).
///
/// It says why it asks (#2494): the [explanation] lines under the button
/// cover which password, where the keys live, and that a wrong try is
/// harmless, and a failure adds [failureHint] under the caller's error. They
/// sit under the button so the field stays in view on a phone.
///
/// It asks for the account password and hands it to [onUnlock]; whether that
/// worked is the caller's, [isBusy] and [error] in. The field is [State] only
/// because Flutter needs its controller to live across rebuilds. Submitting
/// finishes the autofill context and clears the field, so the password does
/// not linger in the widget tree (#2489).
///
/// Key prefixes: `chat_unlock_password` on the field, `chat_unlock_submit` on
/// the button.
class ChatUnlockPrompt extends StatefulWidget {
  /// Creates the prompt.
  const ChatUnlockPrompt({
    required this.onUnlock,
    this.isBusy = false,
    this.error,
    super.key,
  });

  /// Called with the password typed, when it is not empty.
  final ValueChanged<String> onUnlock;

  /// Whether an unlock is running. Holds the button still.
  final bool isBusy;

  /// Why the last unlock failed, already a sentence; null shows nothing.
  final String? error;

  /// What the prompt explains before the field, as (glyph, sentence) pairs.
  static const List<(IconData, String)> explanation = [
    (
      QuarkIcons.key_rounded,
      "It's the same password you sign in to Quark with. There is no second "
          'password to remember.',
    ),
    (
      QuarkIcons.lock_outline,
      'Your message keys are stored locked with that password, so only you '
          'can open them. A browser holds them open only until the tab '
          'reloads or closes, which is why it asks again.',
    ),
    (
      QuarkIcons.check_circle_outline,
      'A wrong password changes nothing. Your messages stay safe; just try '
          'again.',
    ),
  ];

  /// Said under a failed unlock: what to try next.
  static const String failureHint =
      'Check Caps Lock, and use the password you sign in to Quark with.';

  @override
  State<ChatUnlockPrompt> createState() => _ChatUnlockPromptState();
}

class _ChatUnlockPromptState extends State<ChatUnlockPrompt> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (widget.isBusy || password.isEmpty) return;
    TextInput.finishAutofillContext();
    _password.clear();
    widget.onUnlock(password);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(QuarkIcons.lock_outline, size: 40, color: tokens.primary),
              SizedBox(height: tokens.spacingMd),
              Text(
                'Unlock your messages',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spacingSm),
              Text(
                'Messages are encrypted on your devices. Enter your account '
                'password to read them in this browser.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.mutedForeground),
              ),
              SizedBox(height: tokens.spacingLg),
              if (error != null) ...[
                ErrorBanner(message: error),
                SizedBox(height: tokens.spacingSm),
                Text(
                  ChatUnlockPrompt.failureHint,
                  style: TextStyle(color: tokens.mutedForeground),
                ),
                SizedBox(height: tokens.spacingMd),
              ],
              AutofillGroup(
                child: TextField(
                  key: const ValueKey('chat_unlock_password'),
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              SizedBox(height: tokens.spacingMd),
              FilledButton(
                key: const ValueKey('chat_unlock_submit'),
                onPressed: widget.isBusy ? null : _submit,
                child: widget.isBusy
                    ? const QuarkLoader(size: 20)
                    : const Text('Unlock'),
              ),
              SizedBox(height: tokens.spacingLg),
              for (final (icon, line) in ChatUnlockPrompt.explanation)
                Padding(
                  padding: EdgeInsets.only(bottom: tokens.spacingSm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: tokens.mutedForeground),
                      SizedBox(width: tokens.spacingSm),
                      Expanded(
                        child: Text(
                          line,
                          style: TextStyle(color: tokens.mutedForeground),
                        ),
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
