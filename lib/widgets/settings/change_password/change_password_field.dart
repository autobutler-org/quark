import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_icons/quark_icons.dart';

/// One of the change-password dialog's three password fields (#3022), and
/// the new-recovery-phrase dialog's one (#3183).
///
/// Hidden by default, with a toggle to show it, so someone typing on a phone
/// can check what they typed. It only collects: the dialog reads
/// [controller] on submit.
///
/// Key prefixes: `${keyPrefix}_field` on the field and
/// `${keyPrefix}_visibility` on the toggle.
///
/// ```dart
/// ChangePasswordField(
///   keyPrefix: 'change_password_current',
///   label: 'Current password',
///   controller: currentController,
///   autofillHints: const [AutofillHints.password],
///   enabled: !isWorking,
///   onChanged: (_) => setState(() {}),
///   onSubmitted: (_) => submit(),
/// )
/// ```
class ChangePasswordField extends StatefulWidget {
  /// Creates a password field whose keys start with [keyPrefix].
  const ChangePasswordField({
    required this.keyPrefix,
    required this.label,
    required this.controller,
    required this.autofillHints,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  /// Starts the field's and the toggle's `ValueKey`s.
  final String keyPrefix;

  /// What the field asks for, shown as its hint and in the toggle's tooltip.
  final String label;

  /// Holds what has been typed. The dialog reads it on submit.
  final TextEditingController controller;

  /// What a password manager should offer: the stored password or a new one.
  final Iterable<String> autofillHints;

  /// False while the change is in flight.
  final bool enabled;

  /// Called on every edit, so the dialog can re-check what was typed.
  final ValueChanged<String> onChanged;

  /// Called when the keyboard's done action is pressed.
  final ValueChanged<String> onSubmitted;

  /// Whether the field takes focus when the dialog opens.
  final bool autofocus;

  @override
  State<ChangePasswordField> createState() => _ChangePasswordFieldState();
}

class _ChangePasswordFieldState extends State<ChangePasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final label = widget.label.toLowerCase();
    return QuarkWidget.textField(
      key: ValueKey('${widget.keyPrefix}_field'),
      controller: widget.controller,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      hintText: widget.label,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: IconButton(
        key: ValueKey('${widget.keyPrefix}_visibility'),
        icon: Icon(
          _obscured
              ? QuarkIcons.visibility_outlined
              : QuarkIcons.visibility_off_outlined,
        ),
        tooltip: _obscured ? 'Show $label' : 'Hide $label',
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}
