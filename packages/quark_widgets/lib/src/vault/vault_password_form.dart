import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// The password prompt that sets up or unlocks a vault: an icon, a headline,
/// a sentence, the password field, an optional second password field when
/// [secondPasswordLabel] is set, an optional recovery phrase field when
/// [phraseHelp] is set, and the submit button. An optional secondary action
/// sits under it, such as starting over. The first password is asked once:
/// the caller checks it, as the Quark re-confirms a vault's setup password.
/// A restored vault passes [secondPasswordLabel] so the person can type the
/// password they sign in with now beside the one the vault was backed up with.
///
/// What the password opens, and whether it did, is the caller's: [isBusy]
/// and [error] come in, the typed password goes out through [onSubmit]. The
/// fields are [State] only because Flutter needs their controllers to live
/// across rebuilds; a submit clears them, so a password does not linger in
/// the widget tree.
///
/// Key prefixes: `vault_password_field`, `vault_password_login`,
/// `vault_password_phrase`, `vault_password_submit` and
/// `vault_password_secondary`.
///
/// ```dart
/// VaultPasswordForm(
///   title: 'Your vault is locked',
///   message: 'Enter the password you sign in with.',
///   submitLabel: 'Unlock',
///   isBusy: controller.isBusy,
///   error: unlockError,
///   onSubmit: (password, _, [second = '']) =>
///       controller.unlock(password, loginPassword: second),
/// );
/// ```
class VaultPasswordForm extends StatefulWidget {
  /// Creates the prompt.
  const VaultPasswordForm({
    required this.title,
    required this.message,
    required this.submitLabel,
    required this.onSubmit,
    this.icon = QuarkIcons.lock_outline,
    this.phraseHelp,
    this.secondPasswordLabel,
    this.isBusy = false,
    this.error,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  /// The headline.
  final String title;

  /// The sentence under it: which password, and what it does.
  final String message;

  /// The submit button's label, such as "Unlock".
  final String submitLabel;

  /// Called with the password, the recovery phrase (empty when that field is
  /// hidden or was left blank), and the second password when
  /// [secondPasswordLabel] is set. Never called with an empty password, nor
  /// with an empty second password when that field is shown.
  final void Function(String password, String phrase, [String secondPassword])
  onSubmit;

  /// The glyph above the headline.
  final IconData icon;

  /// The help under an optional "Recovery phrase" field, saying what giving
  /// it does. Null hides the field.
  final String? phraseHelp;

  /// The label of a second password field, shown under the first. Null hides
  /// it. The field's key is `vault_password_login`.
  final String? secondPasswordLabel;

  /// Whether a submit is running. Holds both buttons still.
  final bool isBusy;

  /// Why the last submit failed, composed by the caller. Null shows nothing.
  final String? error;

  /// The secondary button's label. Null, or a null [onSecondary], hides it.
  final String? secondaryLabel;

  /// Called when the secondary button is tapped.
  final VoidCallback? onSecondary;

  @override
  State<VaultPasswordForm> createState() => _VaultPasswordFormState();
}

class _VaultPasswordFormState extends State<VaultPasswordForm> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _login = TextEditingController();
  final TextEditingController _phrase = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _login.dispose();
    _phrase.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    final second = _login.text;
    if (widget.isBusy || password.isEmpty) return;
    if (widget.secondPasswordLabel != null && second.isEmpty) return;
    final phrase = _phrase.text;
    TextInput.finishAutofillContext();
    _password.clear();
    _login.clear();
    _phrase.clear();
    widget.onSubmit(password, phrase, second);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;
    final secondaryLabel = widget.secondaryLabel;
    final onSecondary = widget.onSecondary;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(widget.icon, size: 48, color: tokens.primary),
                SizedBox(height: tokens.spacingMd),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: tokens.spacingSm),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.mutedForeground),
                ),
                SizedBox(height: tokens.spacingLg),
                TextField(
                  key: const ValueKey('vault_password_field'),
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
                if (widget.secondPasswordLabel case final label?) ...[
                  SizedBox(height: tokens.spacingMd),
                  TextField(
                    key: const ValueKey('vault_password_login'),
                    controller: _login,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (widget.phraseHelp case final help?) ...[
                  SizedBox(height: tokens.spacingMd),
                  TextField(
                    key: const ValueKey('vault_password_phrase'),
                    controller: _phrase,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Recovery phrase (optional)',
                      helperText: help,
                      helperMaxLines: 5,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (error != null) ...[
                  SizedBox(height: tokens.spacingSm),
                  Text(error, style: TextStyle(color: tokens.error)),
                ],
                SizedBox(height: tokens.spacingLg),
                FilledButton(
                  key: const ValueKey('vault_password_submit'),
                  onPressed: widget.isBusy ? null : _submit,
                  child: widget.isBusy
                      ? const QuarkLoader(size: 20)
                      : Text(widget.submitLabel),
                ),
                if (secondaryLabel != null && onSecondary != null) ...[
                  SizedBox(height: tokens.spacingSm),
                  TextButton(
                    key: const ValueKey('vault_password_secondary'),
                    onPressed: widget.isBusy ? null : onSecondary,
                    child: Text(secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
