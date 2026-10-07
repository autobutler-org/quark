import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/remote_access_setup_stage.dart';
import '../theme/quark_tokens.dart';
import 'remote_access_setup_view/remote_access_setup_point.dart';
import 'remote_access_setup_view/remote_access_setup_step.dart';

/// The content of the remote access setup sheet: what remote access does
/// and a button to turn it on, then a checklist that follows the Quark as it
/// connects, then a done screen.
///
/// The caller moves [stage] along as the Quark reports its state; the view
/// only shows where it is. Closing the sheet partway is fine, because setup
/// carries on on the Quark, and the view says so. Nothing here names the
/// networking underneath: the reader is told what happens, not how.
///
/// Key prefixes: `remote_access_setup_turn_on`,
/// `remote_access_setup_not_now`, `remote_access_setup_done`, and
/// `remote_access_setup_step_<n>` on each checklist row, counting from 1.
///
/// ```dart
/// RemoteAccessSetupView(
///   stage: controller.setupStage,
///   onTurnOn: controller.enable,
///   onNotNow: () => Navigator.of(context).pop(),
///   onDone: () => Navigator.of(context).pop(),
/// );
/// ```
class RemoteAccessSetupView extends StatelessWidget {
  /// Creates the view at [stage].
  const RemoteAccessSetupView({
    required this.stage,
    this.onTurnOn,
    this.onNotNow,
    this.onDone,
    super.key,
  });

  /// How far setup has got.
  final RemoteAccessSetupStage stage;

  /// Turns remote access on, from the intro.
  final VoidCallback? onTurnOn;

  /// Leaves the intro without turning anything on.
  final VoidCallback? onNotNow;

  /// Closes the done screen.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final heading = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final muted = TextStyle(color: tokens.secondaryForeground);

    if (stage == RemoteAccessSetupStage.intro) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingLg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: tokens.spacingSm,
            children: [
              Text('Turn on remote access', style: heading),
              Text(
                'Use Quark away from home the same way you use it on your '
                'Wi‑Fi.',
                style: muted,
              ),
            ],
          ),
          const RemoteAccessSetupPoint(
            icon: QuarkIcons.devices,
            title: 'Works wherever you are',
            body:
                "On mobile data, at a friend's house, or traveling. Nothing "
                'to change on your router.',
          ),
          const RemoteAccessSetupPoint(
            icon: QuarkIcons.lock_outline,
            title: 'Private to your household',
            body:
                'Your Quark gets its own encrypted connection. Only your '
                "household's devices can use it, and everyone still signs in.",
          ),
          const RemoteAccessSetupPoint(
            icon: QuarkIcons.home_rounded,
            title: 'Home stays direct',
            body:
                'On your Wi‑Fi the app still talks to your Quark directly. '
                "Remote access is only used when you're away.",
          ),
          const RemoteAccessSetupPoint(
            icon: QuarkIcons.pause,
            title: 'Off whenever you want',
            body:
                'Turn it off in Settings whenever you like. At home, your '
                'Quark keeps working either way.',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: tokens.spacingSm,
            children: [
              FilledButton(
                key: const ValueKey('remote_access_setup_turn_on'),
                onPressed: onTurnOn,
                child: const Text('Turn on remote access'),
              ),
              TextButton(
                key: const ValueKey('remote_access_setup_not_now'),
                onPressed: onNotNow,
                child: const Text('Not now'),
              ),
              Text(
                'Included with your Quark. No extra account, no '
                'subscription, nothing else to install.',
                textAlign: TextAlign.center,
                style: muted.copyWith(fontSize: 13),
              ),
            ],
          ),
        ],
      );
    }

    final done = stage == RemoteAccessSetupStage.done;
    final connecting = stage == RemoteAccessSetupStage.connecting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: tokens.spacingLg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingSm,
          children: [
            Text(
              done ? 'Remote access is on' : 'Setting up remote access',
              style: heading,
            ),
            Text(
              done
                  ? 'Your Quark can now be reached away from home.'
                  : 'This usually takes under a minute.',
              style: muted,
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Column(
              spacing: tokens.spacingMd,
              children: [
                RemoteAccessSetupStep(
                  key: const ValueKey('remote_access_setup_step_1'),
                  label: 'Preparing a private connection',
                  done: connecting || done,
                  active: !connecting && !done,
                ),
                RemoteAccessSetupStep(
                  key: const ValueKey('remote_access_setup_step_2'),
                  label: 'Connecting your Quark',
                  done: done,
                  active: connecting,
                ),
                RemoteAccessSetupStep(
                  key: const ValueKey('remote_access_setup_step_3'),
                  label: 'Making sure it works',
                  done: done,
                ),
              ],
            ),
          ),
        ),
        if (done)
          FilledButton(
            key: const ValueKey('remote_access_setup_done'),
            onPressed: onDone,
            child: const Text('Done'),
          )
        else
          Text(
            'You can close this. Setup keeps going on your Quark, and '
            "Settings shows when it's ready.",
            textAlign: TextAlign.center,
            style: muted,
          ),
      ],
    );
  }
}
