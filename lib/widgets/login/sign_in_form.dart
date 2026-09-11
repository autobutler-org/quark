import 'package:flutter/material.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:quark/widgets/login/active_host_card.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

class SignInForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocus;
  final FocusNode passwordFocus;
  final bool obscurePassword;
  final bool loading;
  final bool disconnected;
  final String? error;
  final bool managingHosts;
  final VoidCallback onToggleManagingHosts;
  final VoidCallback onHostsChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  /// Manual route to the setup wizard, for a Quark that has no accounts yet.
  ///
  /// The gate normally detects that and redirects, but a slow, failed or
  /// offline probe leaves the user here — so the link is always visible
  /// rather than conditional on a status call that may never answer (#1827).
  final VoidCallback onSetUpQuark;

  const SignInForm({
    super.key,
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocus,
    required this.passwordFocus,
    required this.obscurePassword,
    required this.loading,
    required this.disconnected,
    required this.error,
    required this.managingHosts,
    required this.onToggleManagingHosts,
    required this.onHostsChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onSetUpQuark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo / title
          Icon(
            QuarkIcons.home_filled,
            size: 56,
            color: theme.colorScheme.primary,
            semanticLabel: 'Quark',
          ),
          const SizedBox(height: 16),
          Text(
            'Sign in',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your credentials.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          ActiveHostCard(
            managingHosts: managingHosts,
            onToggleManagingHosts: onToggleManagingHosts,
          ),
          if (managingHosts) ...[
            const SizedBox(height: 8),
            HostManager(onChanged: onHostsChanged),
          ],
          const SizedBox(height: 24),

          // Error banner
          if (disconnected) ...[
            QuarkDisconnectedBanner(onRetry: loading ? null : onSubmit),
            const SizedBox(height: 16),
          ] else if (error != null) ...[
            ErrorBanner(message: error!),
            const SizedBox(height: 16),
          ],

          // Username
          TextFormField(
            controller: usernameController,
            focusNode: usernameFocus,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(QuarkIcons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            autocorrect: false,
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(passwordFocus);
            },
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Username is required' : null,
          ),
          const SizedBox(height: 16),

          // Password
          TextFormField(
            controller: passwordController,
            focusNode: passwordFocus,
            obscureText: obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(QuarkIcons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? QuarkIcons.visibility_outlined
                      : QuarkIcons.visibility_off_outlined,
                ),
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                onPressed: onTogglePassword,
              ),
            ),
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => loading ? null : onSubmit(),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
          ),
          const SizedBox(height: 24),

          // Sign in button
          FilledButton(
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 12),

          // Forgot password
          TextButton(
            onPressed: loading ? null : onForgotPassword,
            child: const Text('Forgot password?'),
          ),

          // Escape hatch to the setup wizard for an unclaimed Quark (#1827).
          TextButton(
            onPressed: loading ? null : onSetUpQuark,
            child: const Text('First time here? Set up this Quark'),
          ),
        ],
      ),
    );
  }
}
