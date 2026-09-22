import 'package:flutter/material.dart';
import 'package:quark/utils/username_rules.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The create-an-account form: a username, a password typed twice, and a
/// submit button.
///
/// Setup uses it for the owner account and the request-account page for a
/// requested one, so the heading, the line under it and the button label are
/// parameters. The username field checks the Quark's rule for new accounts
/// (see [validateNewUsername]).
class SetupForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final FocusNode usernameFocus;
  final FocusNode passwordFocus;
  final FocusNode confirmFocus;
  final bool obscurePassword;
  final bool obscureConfirm;
  final bool loading;
  final String? error;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;

  /// The heading.
  final String title;

  /// The line under [title], saying what the account is for.
  final String subtitle;

  /// The submit button's label.
  final String submitLabel;

  /// Shown between the subtitle and the fields — the setup page's host
  /// switcher and connection banner. Nothing when null.
  final Widget? header;

  const SetupForm({
    super.key,
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.confirmController,
    required this.usernameFocus,
    required this.passwordFocus,
    required this.confirmFocus,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.loading,
    required this.error,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
    this.title = 'Set up your quark',
    this.subtitle =
        'Create your owner account. This is the only account that can manage '
        'the quark.',
    this.submitLabel = 'Create account',
    this.header,
  });

  @override
  State<SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends State<SetupForm> {
  void _onPasswordChanged() {
    // Re-validate so the confirm field updates its error state in real-time
    // when the password field changes after the confirm field has been touched.
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    widget.passwordController.removeListener(_onPasswordChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: widget.formKey,
      // Deliberately not set here. A Form-level onUserInteraction validates
      // every field the moment any one of them is touched, so typing a
      // username put "Password is required" under two fields the user had
      // not reached yet (#2008). Each field below carries the mode instead,
      // so a field speaks only about itself, once it has been used.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            QuarkIcons.home_filled,
            size: 56,
            color: theme.colorScheme.primary,
            semanticLabel: 'Quark',
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          if (widget.header != null) widget.header!,

          if (widget.error != null) ...[
            ErrorBanner(message: widget.error!),
            const SizedBox(height: 16),
          ],

          TextFormField(
            controller: widget.usernameController,
            focusNode: widget.usernameFocus,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText: newUsernameHint,
              helperMaxLines: 2,
              errorMaxLines: 3,
              border: OutlineInputBorder(),
              prefixIcon: Icon(QuarkIcons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newUsername],
            autocorrect: false,
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(widget.passwordFocus);
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
            // The Quark refuses a username outside its rule with a 400
            // (#1946), so it is checked here first and never rewritten.
            validator: validateNewUsername,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: widget.passwordController,
            focusNode: widget.passwordFocus,
            obscureText: widget.obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'At least 8 characters',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(QuarkIcons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  widget.obscurePassword
                      ? QuarkIcons.visibility_outlined
                      : QuarkIcons.visibility_off_outlined,
                ),
                tooltip: widget.obscurePassword
                    ? 'Show password'
                    : 'Hide password',
                onPressed: widget.onTogglePassword,
              ),
            ),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(widget.confirmFocus);
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) return 'Password must be at least 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 8),
          PasswordStrengthBar(password: widget.passwordController.text),
          const SizedBox(height: 8),

          TextFormField(
            controller: widget.confirmController,
            focusNode: widget.confirmFocus,
            obscureText: widget.obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(QuarkIcons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  widget.obscureConfirm
                      ? QuarkIcons.visibility_outlined
                      : QuarkIcons.visibility_off_outlined,
                ),
                tooltip: widget.obscureConfirm
                    ? 'Show password'
                    : 'Hide password',
                onPressed: widget.onToggleConfirm,
              ),
            ),
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => widget.loading ? null : widget.onSubmit(),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != widget.passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: widget.loading ? null : widget.onSubmit,
            child: widget.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
