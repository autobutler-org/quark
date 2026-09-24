import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_icons/quark_icons.dart';

/// The password a destructive account action asks for before it runs (#2346).
///
/// Hidden by default, with a toggle to show it, so someone typing on a phone
/// can check what they typed. The Quark checks the password; this only
/// collects it.
///
/// Key prefixes: `${keyPrefix}_password_field` on the field and
/// `${keyPrefix}_password_visibility` on the toggle.
///
/// ```dart
/// ConfirmPasswordField(
///   keyPrefix: 'delete_account',
///   controller: passwordController,
///   onChanged: (_) => setState(() {}),
///   onSubmitted: (_) => submit(),
/// )
/// ```
class ConfirmPasswordField extends StatefulWidget {
  /// Creates a password field whose keys start with [keyPrefix].
  const ConfirmPasswordField({
    required this.keyPrefix,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    super.key,
  });

  /// Starts the field's and the toggle's `ValueKey`s.
  final String keyPrefix;

  /// Holds what has been typed. The caller reads it on submit.
  final TextEditingController controller;

  /// Called on every edit, so the caller can enable its submit button.
  final ValueChanged<String> onChanged;

  /// Called when the keyboard's done action is pressed.
  final ValueChanged<String> onSubmitted;

  @override
  State<ConfirmPasswordField> createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<ConfirmPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.textField(
      key: ValueKey('${widget.keyPrefix}_password_field'),
      controller: widget.controller,
      autofocus: true,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.password],
      hintText: 'Password',
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: IconButton(
        key: ValueKey('${widget.keyPrefix}_password_visibility'),
        icon: Icon(
          _obscured
              ? QuarkIcons.visibility_outlined
              : QuarkIcons.visibility_off_outlined,
        ),
        tooltip: _obscured ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}
