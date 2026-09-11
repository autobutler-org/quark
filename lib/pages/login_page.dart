import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/login/sign_in_form.dart';
import 'package:quark/widgets/quark_connect_form.dart';

/// The app's landing page (#1639).
///
/// It doubles as the escape hatch from a Quark you can't reach: every other
/// route is behind the auth gate, so if the configured host is wrong or
/// unreachable this is the only page the user can get to. It therefore owns
/// host management too — connect the first Quark, switch between saved ones,
/// add, edit and remove.
class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  /// Set when the last sign-in attempt never reached the Quark, so the page
  /// says so plainly instead of rendering a socket error (#1637). This is the
  /// only page that can be reached with an unreachable Quark configured, so it
  /// is where the explanation matters most.
  bool _disconnected = false;

  /// Whether the inline host list is expanded.
  ///
  /// Inline rather than in a dialog or sheet on purpose: switching hosts can
  /// send the router to the terms page, and a route sitting above this one
  /// would be torn down mid-transition (#1623).
  bool _managingHosts = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _disconnected = false;
    });
    try {
      await AuthService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onLoginSuccess();
    } catch (e) {
      debugPrint('[login_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        // An unreachable Quark is not a failed sign-in, and saying so in the
        // credentials banner reads as "wrong password". It gets its own state.
        _disconnected = isQuarkUnreachableError(e);
        _error = _disconnected ? null : Errors.message(e, 'sign in');
        _loading = false;
      });
      // Announce error to screen readers
    }
  }

  void _goToRecover() {
    context.push(AppRoutes.recover);
  }

  void _goToSetup() {
    context.push(AppRoutes.setup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              // Rebuilds when a host is connected, switched or edited, so the
              // page flips between "connect a Quark" and "sign in" on its own.
              child: ValueListenableBuilder<String?>(
                valueListenable: AppSettings.instance.activeHostNotifier,
                builder: (context, activeHost, _) => activeHost == null
                    // Nothing configured yet, so the only useful thing on this
                    // page is pointing the app at a Quark.
                    ? QuarkConnectForm(
                        onConnected: () {
                          if (mounted) setState(() {});
                        },
                      )
                    : SignInForm(
                        formKey: _formKey,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        usernameFocus: _usernameFocus,
                        passwordFocus: _passwordFocus,
                        obscurePassword: _obscurePassword,
                        loading: _loading,
                        disconnected: _disconnected,
                        error: _error,
                        managingHosts: _managingHosts,
                        onToggleManagingHosts: () =>
                            setState(() => _managingHosts = !_managingHosts),
                        onHostsChanged: () {
                          if (mounted) setState(() {});
                        },
                        onTogglePassword: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        onSubmit: _submit,
                        onForgotPassword: _goToRecover,
                        onSetUpQuark: _goToSetup,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
