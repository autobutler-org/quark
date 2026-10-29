/// The app's "can't reach your Quark" states (#1637), in the two shapes the
/// app needs: [QuarkDisconnectedView] takes over a page whose content failed
/// to load, and [QuarkDisconnectedBanner] sits above a page that stays usable.
///
/// Both are for the case where a Quark *is* configured and simply cannot be
/// reached — off the local network, remote access down, device asleep. The
/// zero-config case belongs to the app's connect form; that is not this.
///
/// The copy says only what the app actually knows. It does not guess between
/// DNS, TLS and timeout, and it never shows the underlying exception: a
/// misattributed cause reads as authoritative and sends people off to fix the
/// wrong thing (#1627). That is why these strings are fixed rather than
/// composed — they are the one case where the sentence does not depend on the
/// thrown object, so it does not have to come from the app.
///
/// The two shapes live in one file because they are one message in two sizes.
/// The headline, the steps and the bullet rendering are shared, and letting
/// them drift apart is the inconsistency this replaces.
library;

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_disconnected_state/troubleshooting_list.dart';

/// Headline for both shapes. A plain statement of fact, no error vocabulary.
const String quarkDisconnectedHeadline = "You're not connected";

/// One-line explanation shown under the headline.
const String quarkDisconnectedBody =
    "The app can't reach your Quark right now.";

/// Headline and body on one line, for somewhere neither shape fits — a form's
/// error line, a single row in a settings list. Still says the same thing, so
/// a user who sees both does not have to reconcile two wordings.
const String quarkDisconnectedInline =
    "You're not connected — the app can't reach your Quark right now.";

/// Terse form, for a row in a list where a [QuarkDisconnectedBanner] on the
/// same page already carries the explanation and the steps.
const String quarkDisconnectedShort = 'Not connected';

/// What a browser can check when the Quark is unreachable.
///
/// A browser cannot use remote access, and it cannot tell why the Quark is
/// out of reach, so each step has to hold for every cause. A phone passes
/// [QuarkUnreachableReason] instead of this list. Nothing here asks the
/// person to retry: the app retries by itself, and the retry button is the
/// only control that tries again.
const List<String> quarkTroubleshootingSteps = [
  "Make sure you're on your home Wi‑Fi.",
  'Make sure your Quark is switched on.',
  'Check the Quark address in Settings.',
];

/// [quarkTroubleshootingSteps] for pages that already show host management —
/// Settings and login — where "go to Settings" is advice to stay put.
///
/// Says nothing about *where* on the page the address is. Direction does not
/// survive contact with a real layout: login puts the host card above this
/// state, Settings puts host management below it, and either can move. Naming
/// a destination the user navigates to ("in Settings") is stable; pointing at
/// a screen position is not.
const List<String> quarkTroubleshootingStepsInPlace = [
  "Make sure you're on your home Wi‑Fi.",
  'Make sure your Quark is switched on.',
  'Check the Quark address.',
];

/// Why a phone cannot reach its Quark, when the phone already knows (#3776).
///
/// Shown in place of [quarkTroubleshootingSteps]. A browser cannot tell these
/// apart and does not use remote access, so it keeps the checklist.
enum QuarkUnreachableReason {
  /// This phone has not finished setting up remote access.
  notSetUp(
    'Finish setting up at home.',
    "This phone isn't set up for remote access yet. Next time you're on "
        'your home Wi‑Fi, open Quark. It sets itself up in a few seconds, '
        'and then works away from home.',
  ),

  /// Remote access is paused on this phone.
  paused('Remote access is paused.', 'You paused it on this phone.'),

  /// The phone can use remote access, but the Quark is not answering.
  notAnswering(
    "Your Quark isn't answering.",
    'It may be switched off, or your home internet may be down. '
        "We'll reconnect by ourselves.",
  ),

  /// This phone has no internet connection.
  noInternet(
    'No internet on this phone.',
    "Quark will reconnect as soon as you're back online.",
  ),

  /// This network wants a sign-in before it lets traffic through.
  needsSignIn(
    'This Wi‑Fi needs a sign-in first.',
    "Sign in or accept the network's terms in your browser, or switch to "
        'mobile data. Quark reconnects by itself.',
  );

  /// Creates a reason with the headline and the sentence under it.
  const QuarkUnreachableReason(this.headline, this.body);

  /// The line that replaces [quarkDisconnectedHeadline].
  final String headline;

  /// The sentence that replaces [quarkDisconnectedBody] and the checklist.
  final String body;
}

/// The words both shapes show: a phone's reason, or the browser checklist.
({String headline, String body, List<String>? steps}) _disconnectedCopy({
  required QuarkUnreachableReason? unreachableReason,
  required List<String> steps,
}) {
  final known = unreachableReason ?? QuarkDisconnectedView.reason;
  if (known != null) {
    return (headline: known.headline, body: known.body, steps: null);
  }
  return (
    headline: quarkDisconnectedHeadline,
    body: quarkDisconnectedBody,
    steps: steps,
  );
}

/// Full-page disconnected state, for a page with nothing left to show.
///
/// A browser shows [quarkTroubleshootingSteps]. A phone that already knows
/// why passes [unreachableReason], or the app sets [reason], and that
/// reason replaces the checklist.
///
/// Key prefixes: `disconnected_retry`, `disconnected_manage_hosts`, and
/// `disconnected_turn_on_remote_access` on the buttons, each rendered only
/// when its callback is supplied.
///
/// ```dart
/// QuarkDisconnectedView(
///   hostAddress: settings.activeHost,
///   onRetry: controller.refresh,
///   onManageHosts: () => context.go(AppRoutes.settings),
/// );
/// ```
class QuarkDisconnectedView extends StatelessWidget {
  /// Creates the full-page disconnected state.
  const QuarkDisconnectedView({
    super.key,
    this.hostAddress,
    this.onRetry,
    this.onManageHosts,
    this.manageHostsLabel = 'Check the address',
    this.steps = quarkTroubleshootingSteps,
    this.onTurnOnRemoteAccess,
    this.unreachableReason,
  });

  /// The address the app tried and could not reach, shown under the body so a
  /// user with several Quarks can see which one this is about. Omit it, or
  /// pass an empty string, when the app has no address to name.
  final String? hostAddress;

  /// Re-runs whatever load failed. Usually the page's own refresh. The retry
  /// button is hidden when this is null.
  final VoidCallback? onRetry;

  /// Takes the user to where the Quark address can be corrected. Omit on pages
  /// that already show host management, so the button never leads nowhere.
  final VoidCallback? onManageHosts;

  /// The label on the [onManageHosts] button.
  final String manageHostsLabel;

  /// The troubleshooting checklist, in the order it is worth checking.
  ///
  /// Ignored when [unreachableReason] or [reason] is set. A phone shows
  /// that reason instead of a checklist.
  final List<String> steps;

  /// Ends a pause of remote access on this phone. Null hides the button
  /// unless [turnOnRemoteAccess] is set.
  ///
  /// Key: `disconnected_turn_on_remote_access`.
  final VoidCallback? onTurnOnRemoteAccess;

  /// Why this phone cannot reach the Quark, when the phone already knows.
  ///
  /// Replaces the checklist with that reason's own words. Null keeps
  /// [steps]. Wins over [reason] when both are set.
  final QuarkUnreachableReason? unreachableReason;

  /// Set while remote access is paused on this phone, so a page that already
  /// builds this view can offer the button without a new argument.
  static VoidCallback? turnOnRemoteAccess;

  /// [unreachableReason] for pages that already build this view.
  ///
  /// The app sets it on a phone, from the reason the phone already knows,
  /// and leaves it null on a browser. Null keeps [steps].
  static QuarkUnreachableReason? reason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final address = hostAddress;
    final turnOn = onTurnOnRemoteAccess ?? turnOnRemoteAccess;
    final copy = _disconnectedCopy(
      unreachableReason: unreachableReason,
      steps: steps,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingXl,
        vertical: tokens.spacingLg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                QuarkIcons.cloud_off_outlined,
                size: 56,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              SizedBox(height: tokens.spacingMd),
              Text(
                copy.headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: tokens.spacingSm),
              Text(
                copy.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (address != null && address.isNotEmpty) ...[
                SizedBox(height: tokens.spacingXs),
                Text(
                  address,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
              if (copy.steps case final checklist?) ...[
                SizedBox(height: tokens.spacingLg),
                TroubleshootingList(steps: checklist),
              ],
              SizedBox(height: tokens.spacingLg),
              Wrap(
                spacing: tokens.spacingSm + tokens.spacingXs,
                runSpacing: tokens.spacingSm + tokens.spacingXs,
                alignment: WrapAlignment.center,
                children: [
                  if (turnOn != null)
                    FilledButton(
                      key: const ValueKey('disconnected_turn_on_remote_access'),
                      onPressed: turnOn,
                      child: const Text('Turn on remote access'),
                    ),
                  if (onRetry != null)
                    FilledButton.icon(
                      key: const ValueKey('disconnected_retry'),
                      onPressed: onRetry,
                      icon: const Icon(QuarkIcons.refresh),
                      label: const Text('Try again'),
                    ),
                  if (onManageHosts != null)
                    OutlinedButton(
                      key: const ValueKey('disconnected_manage_hosts'),
                      onPressed: onManageHosts,
                      child: Text(manageHostsLabel),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact disconnected state, for a page that stays usable while
/// disconnected — Settings and login, where the fix lives on the page itself.
///
/// Uses [quarkTroubleshootingStepsInPlace] unless [unreachableReason] or
/// [QuarkDisconnectedView.reason] names why this phone cannot reach the
/// Quark. That reason replaces the checklist.
///
/// Key prefixes: `disconnected_banner_retry` on the retry button, rendered
/// only when [onRetry] is supplied.
///
/// ```dart
/// QuarkDisconnectedBanner(onRetry: controller.refresh);
/// ```
class QuarkDisconnectedBanner extends StatelessWidget {
  /// Creates the compact disconnected banner.
  const QuarkDisconnectedBanner({
    super.key,
    this.onRetry,
    this.steps = quarkTroubleshootingStepsInPlace,
    this.unreachableReason,
  });

  /// Re-runs whatever load failed. The retry button is hidden when null.
  final VoidCallback? onRetry;

  /// The troubleshooting checklist. Defaults to the in-place wording, which
  /// does not send the user to a page they are already on.
  ///
  /// Ignored when [unreachableReason] or [QuarkDisconnectedView.reason] is
  /// set.
  final List<String> steps;

  /// Why this phone cannot reach the Quark, when the phone already knows.
  ///
  /// Replaces the checklist. Null reads [QuarkDisconnectedView.reason], and
  /// null there keeps [steps].
  final QuarkUnreachableReason? unreachableReason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final copy = _disconnectedCopy(
      unreachableReason: unreachableReason,
      steps: steps,
    );

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(tokens.spacingMd),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  QuarkIcons.cloud_off_outlined,
                  size: 20,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                SizedBox(width: tokens.spacingSm),
                Expanded(
                  child: Text(
                    copy.headline,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacingSm),
            Text(
              copy.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (copy.steps case final checklist?) ...[
              SizedBox(height: tokens.spacingSm + tokens.spacingXs),
              TroubleshootingList(steps: checklist),
            ],
            if (onRetry != null) ...[
              SizedBox(height: tokens.spacingXs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('disconnected_banner_retry'),
                  onPressed: onRetry,
                  icon: const Icon(QuarkIcons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
