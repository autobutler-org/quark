import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// The one password box: hidden while typed, with a button that shows it.
///
/// The field owns whether the text is hidden and the button that flips it,
/// so a screen holds no flag of its own. It also owns the look: the theme's
/// outlined field, an optional lock glyph in front, and no autocorrect or
/// suggestions. The caller owns the words, the autofill hints and the
/// validator.
///
/// [trailingBuilder] adds buttons after the show button. It is handed a
/// `reveal` callback, so a generate button can show the password it wrote.
///
/// Key prefixes: none of its own. The caller's `key` sits on the field, so
/// `enterText` and `find.descendant` reach the text through it, and
/// [visibilityKey] sits on the show button.
///
/// ```dart
/// QuarkPasswordField(
///   key: const ValueKey('delete_account_password_field'),
///   hintText: 'Password',
///   controller: passwordController,
///   autofillHints: const [AutofillHints.password],
///   visibilityKey: const ValueKey('delete_account_password_visibility'),
///   onSubmitted: (_) => submit(),
/// );
/// ```
class QuarkPasswordField extends StatefulWidget {
  /// Creates a hidden password field.
  const QuarkPasswordField({
    this.controller,
    this.focusNode,
    this.formFieldKey,
    this.labelText,
    this.hintText,
    this.helperText,
    this.showLockIcon = false,
    this.visibilityLabel = 'password',
    this.visibilityKey,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.autovalidateMode,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.trailingBuilder,
    super.key,
  });

  /// Holds what has been typed.
  final TextEditingController? controller;

  /// The focus, when the caller moves it from field to field.
  final FocusNode? focusNode;

  /// The key on the inner form field, for a caller that validates this field
  /// on its own, as a confirm field does when the password above it changes.
  final GlobalKey<FormFieldState<String>>? formFieldKey;

  /// The floating label, such as "Password".
  final String? labelText;

  /// The placeholder, for a field with no label.
  final String? hintText;

  /// The line under the field, such as "At least 8 characters".
  final String? helperText;

  /// Whether a lock glyph sits in front of the text.
  final bool showLockIcon;

  /// What the show button names: "Show password", "Show current password".
  final String visibilityLabel;

  /// The key on the show button.
  final Key? visibilityKey;

  /// What a password manager should offer: a stored password or a new one.
  final Iterable<String> autofillHints;

  /// The keyboard's action button.
  final TextInputAction? textInputAction;

  /// Whether the field takes the focus when it first appears.
  final bool autofocus;

  /// False while whatever the password is for is in flight.
  final bool enabled;

  /// When [validator] runs. Null leaves it to the enclosing [Form].
  final AutovalidateMode? autovalidateMode;

  /// Returns the error to show under the field, or null when it is fine.
  final FormFieldValidator<String>? validator;

  /// Called with the text on every edit.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard's action button is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Called when the field is tapped.
  final GestureTapCallback? onTap;

  /// Builds the buttons after the show button, handed a callback that shows
  /// the password. Null adds none.
  final Widget Function(BuildContext context, VoidCallback reveal)?
  trailingBuilder;

  @override
  State<QuarkPasswordField> createState() => _QuarkPasswordFieldState();
}

class _QuarkPasswordFieldState extends State<QuarkPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      key: widget.visibilityKey,
      icon: Icon(_obscured ? QuarkIcons.visibility : QuarkIcons.visibility_off),
      tooltip: '${_obscured ? 'Show' : 'Hide'} ${widget.visibilityLabel}',
      onPressed: () => setState(() => _obscured = !_obscured),
    );
    final trailing = widget.trailingBuilder?.call(
      context,
      () => setState(() => _obscured = false),
    );
    return TextFormField(
      key: widget.formFieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      autovalidateMode: widget.autovalidateMode,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        prefixIcon: widget.showLockIcon
            ? const Icon(QuarkIcons.lock_outline)
            : null,
        suffixIcon: trailing == null
            ? toggle
            : Row(mainAxisSize: MainAxisSize.min, children: [toggle, trailing]),
      ),
    );
  }
}
