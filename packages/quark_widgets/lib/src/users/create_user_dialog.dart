import 'package:flutter/material.dart';

import '../core/password_strength_bar.dart';
import '../models/create_user_input.dart';
import '../theme/quark_tokens.dart';

/// The form an admin fills in to add an account: a username, an initial
/// password typed twice, and whether the account gets a private folder.
///
/// It does not close itself. [onSubmit] receives the input once every field
/// validates, and [onCancel] fires on the cancel button; the caller that
/// pushed the dialog pops it, usually once the Quark has accepted the account.
/// While that request is out the caller passes [isSubmitting], and a refusal
/// comes back in as [error], so the dialog stays open with what was typed.
///
/// The username follows the Quark's rule: up to 32 lowercase letters,
/// numbers, dots, dashes or underscores, starting with a letter or number. It
/// is checked as typed and never rewritten, so what is submitted is exactly
/// what the admin saw.
///
/// The text fields and the checkbox are [State] because they are the form's
/// own transient input, thrown away when the dialog closes. The outcome
/// leaves through [onSubmit].
///
/// Key prefixes: `create_user_username`, `create_user_password`,
/// `create_user_confirm`, `create_user_private_folder`, `create_user_cancel`,
/// and `create_user_submit`.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => CreateUserDialog(
///     isSubmitting: controller.isCreating,
///     error: createError,
///     onSubmit: create,
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class CreateUserDialog extends StatefulWidget {
  /// Creates the add-account form.
  const CreateUserDialog({
    required this.onSubmit,
    required this.onCancel,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  /// Called with the finished input once every field validates.
  final ValueChanged<CreateUserInput> onSubmit;

  /// Called when the admin dismisses the dialog through its cancel button.
  final VoidCallback onCancel;

  /// Whether the account is being created. Disables both buttons.
  final bool isSubmitting;

  /// A sentence saying why the last attempt was refused, composed by the
  /// caller. Shown above the buttons.
  final String? error;

  /// The rule a new username has to meet, the same one the Quark applies.
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,31}$');

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _createFolder = true;

  @override
  void initState() {
    super.initState();
    // Redraws the strength bar as the password is typed.
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  String? _validateUsername(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Username is required';
    if (!CreateUserDialog.usernamePattern.hasMatch(v)) {
      return 'Use up to 32 lowercase letters, numbers, dots, dashes or '
          'underscores, starting with a letter or number';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirm(String? value) =>
      value != _passwordController.text ? 'Passwords do not match' : null;

  void _submit() {
    if (widget.isSubmitting || !_formKey.currentState!.validate()) return;
    widget.onSubmit(
      CreateUserInput(
        username: _usernameController.text,
        password: _passwordController.text,
        createFolder: _createFolder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;

    return AlertDialog(
      title: const Text('Add a user'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('create_user_username'),
                  controller: _usernameController,
                  autofocus: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText:
                        'Lowercase letters, numbers, dots, dashes or '
                        'underscores',
                    helperMaxLines: 2,
                    errorMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validateUsername,
                ),
                SizedBox(height: tokens.spacingMd),
                TextFormField(
                  key: const ValueKey('create_user_password'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validatePassword,
                ),
                SizedBox(height: tokens.spacingSm),
                PasswordStrengthBar(password: _passwordController.text),
                SizedBox(height: tokens.spacingSm),
                TextFormField(
                  key: const ValueKey('create_user_confirm'),
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validateConfirm,
                ),
                SizedBox(height: tokens.spacingSm),
                CheckboxListTile(
                  key: const ValueKey('create_user_private_folder'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _createFolder,
                  onChanged: (value) =>
                      setState(() => _createFolder = value ?? false),
                  title: const Text('Create a private folder for this person'),
                ),
                if (error != null) ...[
                  SizedBox(height: tokens.spacingSm),
                  Text(error, style: TextStyle(color: tokens.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('create_user_cancel'),
          onPressed: widget.isSubmitting ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('create_user_submit'),
          onPressed: widget.isSubmitting ? null : _submit,
          child: widget.isSubmitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add user'),
        ),
      ],
    );
  }
}
