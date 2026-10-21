import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// Asks for the account's recovery phrase and password, to wrap the vault
/// and the chat keys under the phrase so a recovery keeps them.
///
/// It only collects: [onSubmit] fires with the phrase and the password as
/// typed, both non-empty, and [isBusy] and [error] come back from the caller,
/// which checks the phrase and closes the dialog once it is added. The
/// fields are [State] only because Flutter needs their controllers to live
/// across rebuilds. The copy scrolls when the window is short.
///
/// Key prefixes: `add_recovery_phrase_phrase` and
/// `add_recovery_phrase_password` on the fields, `add_recovery_phrase_submit`
/// and `add_recovery_phrase_cancel` on the buttons.
///
/// ```dart
/// AddRecoveryPhraseDialog(
///   isBusy: recoveryPhrase.isBusy,
///   error: errorText,
///   onSubmit: (phrase, password) =>
///       recoveryPhrase.add(password: password, phrase: phrase),
///   onCancel: () => Navigator.of(context).pop(),
/// );
/// ```
class AddRecoveryPhraseDialog extends StatefulWidget {
  /// Creates the dialog.
  const AddRecoveryPhraseDialog({
    required this.onSubmit,
    required this.onCancel,
    this.isBusy = false,
    this.error,
    this.title = 'Add your recovery phrase',
    this.explanation =
        'Your recovery phrase resets your password if you forget it. Add it '
        'here so a recovery keeps your vault and messages. Quark checks the '
        'phrase before it changes anything, so a mistyped one changes nothing.',
    super.key,
  });

  /// Called with the phrase and the password typed, when neither is empty.
  final void Function(String phrase, String password) onSubmit;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// Whether the phrase is being checked and added. Holds the buttons still.
  final bool isBusy;

  /// Why the last try did not go through, composed by the caller. Null shows
  /// nothing.
  final String? error;

  /// The dialog's heading.
  final String title;

  /// What adding the phrase does, said before anything is typed.
  final String explanation;

  @override
  State<AddRecoveryPhraseDialog> createState() =>
      _AddRecoveryPhraseDialogState();
}

class _AddRecoveryPhraseDialogState extends State<AddRecoveryPhraseDialog> {
  final TextEditingController _phrase = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _phrase.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final phrase = _phrase.text.trim();
    final password = _password.text;
    if (widget.isBusy || phrase.isEmpty || password.isEmpty) return;
    widget.onSubmit(phrase, password);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.explanation,
            style: TextStyle(color: tokens.mutedForeground),
          ),
          SizedBox(height: tokens.spacingMd),
          TextField(
            key: const ValueKey('add_recovery_phrase_phrase'),
            controller: _phrase,
            autofocus: true,
            minLines: 2,
            maxLines: 3,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Recovery phrase',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: tokens.spacingSm),
          TextField(
            key: const ValueKey('add_recovery_phrase_password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'The password you sign in to Quark with.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            SizedBox(height: tokens.spacingSm),
            Text(error, style: TextStyle(color: tokens.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('add_recovery_phrase_cancel'),
          onPressed: widget.isBusy ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('add_recovery_phrase_submit'),
          onPressed: widget.isBusy ? null : _submit,
          child: widget.isBusy
              ? const QuarkLoader(size: 20)
              : const Text('Add phrase'),
        ),
      ],
    );
  }
}
