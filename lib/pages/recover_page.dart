import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Password recovery screen — resets password using the recovery phrase.
class RecoverPage extends StatefulWidget {
  final VoidCallback? onRecoverSuccess;

  /// The username typed on the login form, if any, so it need not be retyped.
  final String? initialUsername;

  const RecoverPage({super.key, this.onRecoverSuccess, this.initialUsername});

  @override
  State<RecoverPage> createState() => _RecoverPageState();
}

class _RecoverPageState extends State<RecoverPage> {
  final _formKey = GlobalKey<FormState>();
  late final _usernameController = TextEditingController(
    text: widget.initialUsername,
  );
  final _phraseController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Redraws the strength meter as the password is typed, the way the setup
    // form does it.
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _usernameController.dispose();
    _phraseController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.recover(
        username: _usernameController.text.trim(),
        recoveryPhrase: _phraseController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      if (widget.onRecoverSuccess != null) {
        widget.onRecoverSuccess!();
      } else if (mounted) {
        context.go(AppRoutes.login);
      }
    } catch (e) {
      debugPrint('[recover_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        // An unreachable Quark is not a rejected request; saying so plainly
        // beats a socket error in a form's error banner (#1637).
        _error = Errors.message(e, 'reset your password');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [AppThemeToggle()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      QuarkIcons.key_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'Recovery',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Reset your password',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your username and recovery phrase, then choose a new password.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(QuarkIcons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Username is required'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phraseController,
                      decoration: const InputDecoration(
                        labelText: 'Recovery phrase',
                        hintText: 'word-word-word-word-word-word',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(QuarkIcons.key_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Recovery phrase is required'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(QuarkIcons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? QuarkIcons.visibility_outlined
                                : QuarkIcons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password is required';
                        }
                        if (v.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    // The same meter the setup form shows. Choosing a password
                    // here is the same decision it is there, and it was the
                    // one place in the app that asked for one without saying
                    // how strong it was (#2031).
                    PasswordStrengthBar(password: _passwordController.text),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(QuarkIcons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? QuarkIcons.visibility_outlined
                                : QuarkIcons.visibility_off_outlined,
                          ),
                          tooltip: _obscureConfirm
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() => _obscureConfirm = !_obscureConfirm);
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (v != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Reset password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
