import 'package:flutter/material.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark/widgets/notice_banner.dart';
import 'package:quark/widgets/login/host_switcher.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The username and password form on the login page, with the host switcher, a link to recovery and, on a Quark
/// with no accounts yet, a link to setup.
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

  /// Good news from wherever the user just came from — a password they have
  /// only just reset, say (#2029). Sits above the fields like [error], and
  /// never at the same time as one: an error is about the attempt in front of
  /// the user and wins.
  final String? notice;
  final bool managingHosts;
  final VoidCallback onToggleManagingHosts;
  final VoidCallback onHostsChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;

  /// Repeats whatever found the Quark unreachable — the status check or the
  /// sign-in. Falls back to [onSubmit] when null.
  final VoidCallback? onRetry;
  final VoidCallback onForgotPassword;

  /// Manual route to the setup wizard, for a Quark that has no accounts yet.
  ///
  /// The gate normally detects that and redirects, but a slow, failed or
  /// offline probe leaves the user here — so the link is shown whenever the
  /// app does not *know* the Quark is claimed (#1827). It is hidden only on
  /// the strength of a status call that said so, because on a Quark with an
  /// owner it reads as an onboarding offer on every visit and dilutes the
  /// one action that page is for (#2030).
  final VoidCallback onSetUpQuark;

  /// Opens the request-account page. Null hides the link: the login page
  /// passes it only while the Quark says it takes account requests (#1908).
  final VoidCallback? onRequestAccess;

  /// Whether the Quark is known to have an owner already.
  ///
  /// Null means nobody has answered yet — a probe still in flight, a failed
  /// one, or an unreachable Quark — and that is deliberately treated as "may
  /// still need setting up".
  final bool? setupComplete;

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
    this.notice,
    required this.managingHosts,
    required this.onToggleManagingHosts,
    required this.onHostsChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    this.onRetry,
    required this.onForgotPassword,
    required this.onSetUpQuark,
    this.onRequestAccess,
    this.setupComplete,
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
          // Not "Sign in": the button below says that, and a heading with
          // the same words flattens the hierarchy and gives a Probe script
          // two things to tap for one instruction (#2025).
          Text(
            'Welcome back',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to your Quark.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          HostSwitcher(
            managingHosts: managingHosts,
            onToggleManagingHosts: onToggleManagingHosts,
            onHostsChanged: onHostsChanged,
          ),
          const SizedBox(height: 24),

          // Error banner, or the notice when there is nothing wrong
          if (disconnected) ...[
            QuarkDisconnectedBanner(
              onRetry: loading ? null : onRetry ?? onSubmit,
            ),
            const SizedBox(height: 16),
          ] else if (error != null) ...[
            ErrorBanner(message: error!),
            const SizedBox(height: 16),
          ] else if (notice != null) ...[
            NoticeBanner(message: notice!),
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
            // Revalidates as the user types once they have touched the
            // field, so "Username is required" goes away when they supply
            // one instead of sitting there until the next submit (#2020).
            autovalidateMode: AutovalidateMode.onUserInteraction,
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
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
          ),
          const SizedBox(height: 24),

          // Sign in button
          FilledButton(
            key: const ValueKey('login_submit'),
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const QuarkLoader(size: 20)
                : const Text('Sign in'),
          ),
          const SizedBox(height: 12),

          // Forgot password
          TextButton(
            onPressed: loading ? null : onForgotPassword,
            child: const Text('Forgot password?'),
          ),

          // A second person asks this Quark for an account (#1908).
          if (onRequestAccess != null)
            TextButton(
              key: const ValueKey('sign_in_request_access'),
              onPressed: loading ? null : onRequestAccess,
              child: const Text('Need an account? Request one'),
            ),

          // Escape hatch to the setup wizard for an unclaimed Quark (#1827),
          // hidden once the Quark has said it has an owner (#2030).
          if (setupComplete != true)
            TextButton(
              key: const ValueKey('login_set_up_quark'),
              onPressed: loading ? null : onSetUpQuark,
              child: const Text('First time here? Set up this Quark'),
            ),
        ],
      ),
    );
  }
}
