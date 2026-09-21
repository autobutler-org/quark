import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/login/sign_in_form.dart';
import 'package:quark/widgets/quark_connect_form.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';

/// The app's landing page (#1639).
///
/// It doubles as the escape hatch from a Quark you can't reach: every other
/// route is behind the auth gate, so if the configured host is wrong or
/// unreachable this is the only page the user can get to. It therefore owns
/// host management too — connect the first Quark, switch between saved ones,
/// add, edit and remove.
class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  /// Asks the active Quark for its status, which says whether it takes
  /// account requests. Injectable so a test can answer without a Quark.
  final Future<AuthStatus> Function() checkStatus;

  const LoginPage({
    super.key,
    required this.onLoginSuccess,
    this.checkStatus = AuthService.checkStatus,
    this.initialUsername,
    this.notice,
  });

  /// Fills the username field, so a user who has just proved who they are does
  /// not type it a third time (#2029).
  final String? initialUsername;

  /// Good news from the page that sent the user here — see
  /// [SignInForm.notice].
  final String? notice;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final _usernameController = TextEditingController(
    text: widget.initialUsername ?? '',
  );
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

  /// Whether the active Quark takes account requests, which is what shows the
  /// request link (#1908). False until the Quark says otherwise.
  bool _accessRequestsEnabled = false;

  /// Bumped by every status check, so an answer from a Quark the user has
  /// since switched away from cannot set the link.
  int _statusGeneration = 0;

  /// A sign-in that came back with the account's recovery phrase. Its session
  /// is not stored until the phrase is acknowledged (#1873). While set, the
  /// phrase step replaces the sign-in form.
  LoginResult? _pendingLogin;

  /// Whether the held phrase has been acknowledged.
  bool _phraseAcknowledged = false;

  /// Whether this Quark already has an owner, or null while nobody has
  /// answered — see [SignInForm.setupComplete] (#2030).
  bool? _setupComplete;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.activeHostNotifier.addListener(_onActiveHostChanged);
    _checkAccessRequests();
    _checkSetupState();
  }

  /// Asks the Quark whether it has been claimed, so the setup link is offered
  /// only where it leads somewhere. A failed or unanswered probe leaves
  /// [_setupComplete] null, which keeps the link — the #1827 rule.
  Future<void> _checkSetupState() async {
    if (AppSettings.instance.activeHost == null) return;
    try {
      final status = await authStatusProbe();
      if (!mounted) return;
      setState(() => _setupComplete = status.setupComplete);
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupComplete = null);
    }
  }

  /// A different Quark answers differently, so everything the last one told
  /// us is dropped before the new one is asked.
  ///
  /// That includes the failure banners: "You're offline" belonged to a Quark
  /// the user has just switched away from, and leaving it up over a healthy
  /// one made the new host look broken until they pressed Try again (#2062).
  void _onActiveHostChanged() {
    if (!mounted) return;
    setState(() {
      _setupComplete = null;
      _disconnected = false;
      _error = null;
    });
    _checkAccessRequests();
    _checkSetupState();
  }

  @override
  void dispose() {
    AppSettings.instance.activeHostNotifier.removeListener(
      _onActiveHostChanged,
    );
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
      final result = await AuthService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      // The first sign-in of an admin-created account carries its recovery
      // phrase, and no stored session yet (#1873).
      if (result.recoveryPhrase != null) {
        setState(() {
          _pendingLogin = result;
          _loading = false;
        });
        return;
      }
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

  /// Stores the held session once its phrase has been acknowledged, which
  /// signs the app in (#1873).
  Future<void> _acceptPendingLogin() async {
    final result = _pendingLogin;
    if (result == null || !_phraseAcknowledged) return;
    await AuthService.acceptSession(result);
    if (!mounted) return;
    widget.onLoginSuccess();
  }

  /// Asks the active Quark whether it takes account requests. A Quark that
  /// cannot say gets no link: a request to it would only fail.
  Future<void> _checkAccessRequests() async {
    final generation = ++_statusGeneration;
    var enabled = false;
    if (AppSettings.instance.activeHost != null) {
      try {
        enabled = (await widget.checkStatus()).accessRequestsEnabled;
      } catch (e) {
        debugPrint('[login_page.dart] status check failed: $e');
      }
    }
    if (!mounted || generation != _statusGeneration) return;
    if (enabled == _accessRequestsEnabled) return;
    setState(() => _accessRequestsEnabled = enabled);
  }

  /// Navigates rather than pushes, like [_goToSetup]: a pushed route would
  /// leave the address bar reading /login.
  void _goToRequestAccount() => context.go(AppRoutes.requestAccount);

  void _goToRecover() {
    final username = _usernameController.text.trim();
    context.push(
      Uri(
        path: AppRoutes.recover,
        queryParameters: username.isEmpty ? null : {'username': username},
      ).toString(),
    );
  }

  /// Unlike [_goToRecover] this navigates rather than pushes: go_router's
  /// `optionURLReflectsImperativeAPIs` is false, so a pushed route renders the
  /// setup wizard while the address bar still reads /login (#1827). /setup is
  /// a top-level page, not a drill-down, so `go` is the right call anyway.
  void _goToSetup() {
    context.go(AppRoutes.setup);
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
                    // A held first sign-in shows its recovery phrase until
                    // it is acknowledged; nothing is stored before then, so
                    // the router keeps this page up (#1873).
                    : _pendingLogin != null
                    ? RecoveryPhraseStep(
                        phrase: _pendingLogin!.recoveryPhrase!,
                        acknowledged: _phraseAcknowledged,
                        onAcknowledgedChanged: (value) => setState(
                          () => _phraseAcknowledged = value ?? false,
                        ),
                        onContinue: _acceptPendingLogin,
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
                        notice: widget.notice,
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
                        onRequestAccess: _accessRequestsEnabled
                            ? _goToRequestAccount
                            : null,
                        setupComplete: _setupComplete,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
