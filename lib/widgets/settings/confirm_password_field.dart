import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
class ConfirmPasswordField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return QuarkPasswordField(
      key: ValueKey('${keyPrefix}_password_field'),
      controller: controller,
      autofocus: true,
      hintText: 'Password',
      visibilityKey: ValueKey('${keyPrefix}_password_visibility'),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
