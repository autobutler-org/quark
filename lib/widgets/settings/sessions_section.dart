import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/sessions_controller.dart';
import 'package:quark/models/auth_session.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/relative_time.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Sessions card on the Account tab of Settings (#1663): every place the
/// account is signed in, with a way to sign one out, or all the others.
///
/// Owns a [SessionsController]. Signing out the session in use goes through
/// the app's logout, after which [onSignedOut] leaves the page.
///
/// Keys: `session_tile_<id>`, `session_revoke_<id>`, `sessions_revoke_others`.
class SessionsSection extends StatefulWidget {
  /// Creates the section, with the real service unless [controller] is given.
  const SessionsSection({
    required this.onSignedOut,
    this.controller,
    super.key,
  });

  /// Called once the session in use has been signed out.
  final VoidCallback onSignedOut;

  /// Injected for tests. Created and disposed here when null.
  final SessionsController? controller;

  @override
  State<SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<SessionsSection> {
  late final SessionsController _controller =
      widget.controller ?? SessionsController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _revoke(AuthSession session) async {
    final confirmed = await confirmAction(
      context,
      title: session.current ? 'Sign out?' : 'Sign out that session?',
      message: session.current
          ? 'This is the session you are using. You will need to sign in '
                'again.'
          : 'Whoever is using it will need to sign in again.',
      confirmLabel: 'Sign out',
    );
    if (confirmed != true) return;
    final signedOut = await _controller.revoke(session);
    if (signedOut && session.current && mounted) widget.onSignedOut();
  }

  Future<void> _revokeOthers() async {
    final confirmed = await confirmAction(
      context,
      title: 'Sign out everywhere else?',
      message:
          'Every other session of your account will need to sign in again. '
          'This one stays signed in.',
      confirmLabel: 'Sign out',
    );
    if (confirmed != true) return;
    await _controller.revokeOthers();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final sessions = _controller.sessions;
        return RecordListCard(
          title: 'Sessions',
          subtitle: 'Where your account is signed in',
          isLoading: _controller.isLoading && sessions.isEmpty,
          error: _controller.error,
          keyPrefix: 'session',
          actionKey: 'revoke',
          actionIcon: QuarkIcons.logout,
          actionTooltip: 'Sign out',
          records: [
            for (final session in sessions)
              RecordListItem(
                id: session.id,
                title: session.current ? 'This session' : 'Session',
                subtitle:
                    'Signed in ${formatRelative(session.createdAt)} · '
                    'last used ${formatRelative(session.lastUsedAt)}',
              ),
          ],
          onAction: _controller.isWorking
              ? null
              : (id) => _revoke(sessions.firstWhere((s) => s.id == id)),
          footer: TextButton(
            key: const ValueKey('sessions_revoke_others'),
            onPressed: _controller.hasOthers && !_controller.isWorking
                ? _revokeOthers
                : null,
            child: const Text('Sign out everywhere else'),
          ),
        );
      },
    );
  }
}
