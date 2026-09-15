import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/request_account_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';
import 'package:quark/widgets/setup/setup_form.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks this Quark for an account (#1908): a username and password, then the
/// recovery phrase for the new account, then "request sent".
///
/// Reached from the sign-in form when the Quark takes requests. An admin
/// approves the request on the Users page; until then signing in says the
/// request is waiting.
class RequestAccountPage extends StatefulWidget {
  const RequestAccountPage({super.key});

  @override
  State<RequestAccountPage> createState() => _RequestAccountPageState();
}

class _RequestAccountPageState extends State<RequestAccountPage> {
  final _controller = RequestAccountController();
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _controller.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _controller.submit(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _backToSignIn() => context.go(AppRoutes.login);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final c = _controller;
                  final error = c.error;
                  return switch (c.step) {
                    RequestAccountStep.form => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SetupForm(
                          title: 'Request an account',
                          subtitle:
                              'An admin of this Quark approves new accounts. '
                              'You can sign in once they do.',
                          submitLabel: 'Send request',
                          formKey: _formKey,
                          usernameController: _usernameController,
                          passwordController: _passwordController,
                          confirmController: _confirmController,
                          usernameFocus: _usernameFocus,
                          passwordFocus: _passwordFocus,
                          confirmFocus: _confirmFocus,
                          obscurePassword: _obscurePassword,
                          obscureConfirm: _obscureConfirm,
                          loading: c.isSubmitting,
                          error: error == null
                              ? null
                              : Errors.message(error, 'send the request'),
                          onTogglePassword: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          onToggleConfirm: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                          onSubmit: _submit,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          key: const ValueKey('request_account_back'),
                          onPressed: c.isSubmitting ? null : _backToSignIn,
                          child: const Text('Back to sign in'),
                        ),
                      ],
                    ),
                    RequestAccountStep.phrase => RecoveryPhraseStep(
                      phrase: c.recoveryPhrase!,
                      acknowledged: c.acknowledged,
                      onAcknowledgedChanged: (value) =>
                          c.setAcknowledged(value ?? false),
                      onContinue: c.finish,
                    ),
                    RequestAccountStep.sent => EmptyStateWidget(
                      icon: QuarkIcons.check_circle_outline,
                      headline: 'Request sent',
                      subtext:
                          'An admin of this Quark needs to approve it. Sign in '
                          'once they have.',
                      action: FilledButton(
                        key: const ValueKey('request_account_sign_in'),
                        onPressed: _backToSignIn,
                        child: const Text('Back to sign in'),
                      ),
                    ),
                  };
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
