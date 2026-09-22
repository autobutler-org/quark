import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/login/host_switcher.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';
import 'package:quark/widgets/setup/setup_form.dart';
import 'package:quark/widgets/setup/theme_step.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// First-boot setup screen — creates the owner account on the quark.
///
/// The account step carries the same host switcher as the login page, and
/// every host it lands on is asked whether it has been claimed: one that has
/// sends the user to login, one that cannot be reached says so.
///
/// Three steps:
///  1. Create account (username + password)
///  2. Acknowledge recovery phrase
///  3. Choose app theme (persisted immediately — live preview)
class SetupPage extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupPage({super.key, required this.onSetupComplete});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  /// Set when the status check or the account creation could not reach the
  /// Quark, so the page says so plainly instead of offering a form that can
  /// only fail (#1637). Holds whichever failed, so the banner's retry repeats
  /// it.
  VoidCallback? _retry;

  /// Whether the inline host list is expanded — see [HostSwitcher].
  bool _managingHosts = false;

  /// Bumped by every status check, so an answer from a Quark the user has
  /// since switched away from is dropped.
  int _probeGeneration = 0;

  // Step 2: recovery phrase acknowledgement
  String? _recoveryPhrase;
  bool _phraseAcknowledged = false;

  // Step 3: theme selection
  bool _showThemeStep = false;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.activeHostNotifier.addListener(_onActiveHostChanged);
    _checkSetupState();
  }

  /// Whether the owner account is being created or already exists. From then
  /// on this Quark is ours, so a status answer must not move the user off the
  /// wizard.
  bool get _accountStarted => _loading || _recoveryPhrase != null;

  /// Asks the active Quark whether it has been claimed: a claimed one belongs
  /// on login, an unreachable one gets the disconnected banner.
  Future<void> _checkSetupState() async {
    if (_accountStarted || AppSettings.instance.activeHost == null) return;
    final generation = ++_probeGeneration;
    try {
      final status = await authStatusProbe();
      if (!mounted || generation != _probeGeneration || _accountStarted) return;
      if (status.setupComplete) {
        context.go(AppRoutes.login);
        return;
      }
      setState(() => _retry = null);
    } catch (e) {
      debugPrint('[setup_page.dart] status check failed: $e');
      if (!mounted || generation != _probeGeneration || _accountStarted) return;
      setState(
        () => _retry = isQuarkUnreachableError(e) ? _checkSetupState : null,
      );
    }
  }

  /// A different Quark answers differently, so what the last one said is
  /// dropped before the new one is asked.
  void _onActiveHostChanged() {
    if (!mounted || _accountStarted) return;
    setState(() {
      _retry = null;
      _error = null;
    });
    _checkSetupState();
  }

  @override
  void dispose() {
    AppSettings.instance.activeHostNotifier.removeListener(
      _onActiveHostChanged,
    );
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _retry = null;
    });
    try {
      final result = await AuthService.setup(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _recoveryPhrase = result.recoveryPhrase;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[setup_page.dart] Error: $e');
      if (!mounted) return;
      setState(() {
        // An unreachable Quark is not a rejected request; saying so plainly
        // beats a socket error in a form's error banner (#1637).
        final unreachable = isQuarkUnreachableError(e);
        _retry = unreachable ? _submit : null;
        _error = unreachable ? null : Errors.message(e, 'set up your Quark');
        _loading = false;
      });
    }
  }

  void _confirmPhraseAndProceed() {
    if (_phraseAcknowledged) {
      setState(() => _showThemeStep = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _showThemeStep
                  ? ThemeStep(onContinue: widget.onSetupComplete)
                  : _recoveryPhrase != null
                  ? RecoveryPhraseStep(
                      phrase: _recoveryPhrase!,
                      acknowledged: _phraseAcknowledged,
                      onAcknowledgedChanged: (v) =>
                          setState(() => _phraseAcknowledged = v ?? false),
                      onContinue: _confirmPhraseAndProceed,
                    )
                  : SetupForm(
                      formKey: _formKey,
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      confirmController: _confirmController,
                      usernameFocus: _usernameFocus,
                      passwordFocus: _passwordFocus,
                      confirmFocus: _confirmFocus,
                      obscurePassword: _obscurePassword,
                      obscureConfirm: _obscureConfirm,
                      loading: _loading,
                      error: _error,
                      onTogglePassword: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onToggleConfirm: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      onSubmit: _submit,
                      // The same switcher and banner as the login page, in
                      // the same place: under the heading, above the fields.
                      header: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HostSwitcher(
                            managingHosts: _managingHosts,
                            onToggleManagingHosts: () => setState(
                              () => _managingHosts = !_managingHosts,
                            ),
                            onHostsChanged: () {
                              if (mounted) setState(() {});
                            },
                          ),
                          const SizedBox(height: 24),
                          if (_retry != null) ...[
                            QuarkDisconnectedBanner(
                              onRetry: _loading ? null : _retry,
                            ),
                            const SizedBox(height: 16),
                          ],
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
