import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/remote_access_state.dart';
import '../theme/quark_tokens.dart';
import 'remote_access_panel/remote_access_failure.dart';
import 'remote_access_panel/remote_access_intro.dart';
import 'remote_access_panel/remote_access_status_line.dart';

/// Remote access on the Settings Network tab: what it is and a way to set
/// it up while it is off, and, once it is on, its state and the switch that
/// turns it off for the whole household.
///
/// Only an admin can turn remote access on or off; everyone else reads the
/// same state and is told who can change it. While it is [RemoteAccessState.
/// failing], [failure] and [failureSteps] say what went wrong and what to
/// try, and an admin gets Try again and Turn off. The panel decides nothing:
/// the caller confirms before turning it off, and writes [error] and
/// [failure].
///
/// Key prefixes: `remote_access_retry`, `remote_access_set_up`,
/// `remote_access_coming_soon`, `remote_access_member_note`,
/// `remote_access_switch`, `remote_access_turn_off`,
/// `remote_access_try_again`, `remote_access_get_help`, and
/// `remote_access_status_<state>` on the status line.
///
/// ```dart
/// RemoteAccessPanel(
///   state: controller.state,
///   isAdmin: isAdmin,
///   failure: Errors.remoteAccessFailing,
///   failureSteps: Errors.remoteAccessFailingSteps,
///   onSetUp: openSetup,
///   onTurnOff: confirmTurnOff,
///   onTryAgain: controller.enable,
/// );
/// ```
class RemoteAccessPanel extends StatelessWidget {
  /// Creates the panel.
  const RemoteAccessPanel({
    required this.state,
    required this.isAdmin,
    this.isLoading = false,
    this.isWorking = false,
    this.available = true,
    this.error,
    this.failure,
    this.failureSteps = const [],
    this.onRetry,
    this.onSetUp,
    this.onTurnOff,
    this.onTryAgain,
    this.onGetHelp,
    super.key,
  });

  /// What remote access is doing.
  final RemoteAccessState state;

  /// Whether this user may turn remote access on and off.
  final bool isAdmin;

  /// Whether the state is being read. Shows a loader instead of the panel.
  final bool isLoading;

  /// Whether a change is in flight. Disables every control.
  final bool isWorking;

  /// Whether remote access can be set up from here yet. False says it is
  /// coming soon in place of the set-up button.
  final bool available;

  /// Why the state could not be read, in the caller's words, or null. Shown
  /// with a Retry button in place of the panel.
  final String? error;

  /// What went wrong while [state] is failing, in the caller's words.
  final String? failure;

  /// What to try while [state] is failing, in order.
  final List<String> failureSteps;

  /// Reads the state again after [error].
  final VoidCallback? onRetry;

  /// Starts setting remote access up.
  final VoidCallback? onSetUp;

  /// Asks to turn remote access off for everyone.
  final VoidCallback? onTurnOff;

  /// Turns remote access on again after a failure.
  final VoidCallback? onTryAgain;

  /// Opens help while [state] is failing. Null hides the button.
  final VoidCallback? onGetHelp;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final caption = TextStyle(color: tokens.secondaryForeground, fontSize: 13);
    final error = this.error;
    final failure = this.failure;
    final busy = isWorking ? const QuarkLoader(size: 20) : null;

    final List<Widget> children;
    if (isLoading) {
      children = [const Center(child: QuarkLoader())];
    } else if (error != null) {
      children = [
        Text(error, style: TextStyle(color: tokens.error)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('remote_access_retry'),
            onPressed: onRetry,
            icon: const Icon(QuarkIcons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ),
      ];
    } else if (state == RemoteAccessState.off) {
      children = [
        const RemoteAccessIntro(),
        RemoteAccessStatusLine(state: state),
        if (!available)
          Text(
            'Coming soon. Your Quark is reachable on your home network in '
            'the meantime.',
            key: const ValueKey('remote_access_coming_soon'),
            style: caption,
          )
        else if (isAdmin) ...[
          FilledButton(
            key: const ValueKey('remote_access_set_up'),
            onPressed: isWorking ? null : onSetUp,
            child: busy ?? const Text('Set up remote access'),
          ),
          Text(
            'About 30 seconds. You can turn it off anytime.',
            textAlign: TextAlign.center,
            style: caption,
          ),
        ] else
          Text(
            'An admin turns this on for the whole household. Ask an admin '
            'to turn it on in Settings, on the Network tab.',
            key: const ValueKey('remote_access_member_note'),
            style: caption,
          ),
      ];
    } else {
      final failing = state == RemoteAccessState.failing;
      children = [
        Text(
          'Your Quark',
          style: caption.copyWith(fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            Expanded(child: RemoteAccessStatusLine(state: state)),
            Semantics(
              label: 'Remote access for this Quark',
              child: Switch(
                key: const ValueKey('remote_access_switch'),
                value: true,
                onChanged: isAdmin && !isWorking
                    ? (on) {
                        if (!on) onTurnOff?.call();
                      }
                    : null,
              ),
            ),
          ],
        ),
        if (failing && failure != null)
          RemoteAccessFailure(
            message: failure,
            steps: failureSteps,
            onGetHelp: onGetHelp,
          ),
        if (failing && isAdmin)
          Wrap(
            spacing: tokens.spacingSm,
            runSpacing: tokens.spacingSm,
            children: [
              OutlinedButton(
                key: const ValueKey('remote_access_turn_off'),
                onPressed: isWorking ? null : onTurnOff,
                child: const Text('Turn off'),
              ),
              FilledButton(
                key: const ValueKey('remote_access_try_again'),
                onPressed: isWorking ? null : onTryAgain,
                child: busy ?? const Text('Try again'),
              ),
            ],
          ),
        Text(
          'Only admins can change this. It affects everyone in your '
          'household.',
          style: caption,
        ),
      ];
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: tokens.spacingMd,
          children: children,
        ),
      ),
    );
  }
}
