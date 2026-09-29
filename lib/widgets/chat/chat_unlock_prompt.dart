import 'package:flutter/material.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the chat page shows in place of chat while it is locked: on web after
/// a reload, when the keys that open messages live only in memory (#2416).
///
/// It asks for the account password and hands it to [onUnlock]; whether that
/// worked is the caller's, [isBusy] and [error] in. The field is [State] only
/// because Flutter needs its controller to live across rebuilds.
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
    if (widget.isBusy || _password.text.isEmpty) return;
    widget.onUnlock(_password.text);
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
                SizedBox(height: tokens.spacingMd),
              ],
              TextField(
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
              SizedBox(height: tokens.spacingMd),
              FilledButton(
                key: const ValueKey('chat_unlock_submit'),
                onPressed: widget.isBusy ? null : _submit,
                child: widget.isBusy
                    ? const QuarkLoader(size: 20)
                    : const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
