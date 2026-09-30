/// The app's "can't reach your Quark" states (#1637), in the two shapes the
/// app needs: [QuarkDisconnectedView] takes over a page whose content failed
/// to load, and [QuarkDisconnectedBanner] sits above a page that stays usable.
///
/// Both are for the case where a Quark *is* configured and simply cannot be
/// reached — off the local network, Tailscale down, device asleep. The
/// zero-config case belongs to the app's connect form, and a vault whose USB
/// drive is unplugged has its own state on the vault page; neither is this.
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

/// The troubleshooting steps, in the order they are worth checking.
///
/// Deliberately static: v1 does not autodetect *why* the Quark is unreachable,
/// so every step here has to hold for every cause.
const List<String> quarkTroubleshootingSteps = [
  "Check you're on the same network as your Quark, or connected to it through "
      'Tailscale or another remote access route.',
  'Confirm the Quark address in Settings is correct.',
  'Confirm your Quark is powered on.',
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
  "Check you're on the same network as your Quark, or connected to it through "
      'Tailscale or another remote access route.',
  'Confirm the Quark address is correct.',
  'Confirm your Quark is powered on.',
];

/// Full-page disconnected state, for a page with nothing left to show.
///
/// Key prefixes: `disconnected_retry` and `disconnected_manage_hosts` on the
/// two buttons, each rendered only when its callback is supplied.
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
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final address = hostAddress;

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
                quarkDisconnectedHeadline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: tokens.spacingSm),
              Text(
                quarkDisconnectedBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: tokens.mutedForeground,
                ),
              ),
              if (address != null && address.isNotEmpty) ...[
                SizedBox(height: tokens.spacingXs),
                Text(
                  address,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
                ),
              ],
              SizedBox(height: tokens.spacingLg),
              TroubleshootingList(steps: steps),
              SizedBox(height: tokens.spacingLg),
              Wrap(
                spacing: tokens.spacingSm + tokens.spacingXs,
                runSpacing: tokens.spacingSm + tokens.spacingXs,
                alignment: WrapAlignment.center,
                children: [
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
  });

  /// Re-runs whatever load failed. The retry button is hidden when null.
  final VoidCallback? onRetry;

  /// The troubleshooting checklist. Defaults to the in-place wording, which
  /// does not send the user to a page they are already on.
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);

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
                    quarkDisconnectedHeadline,
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
              quarkDisconnectedBody,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: tokens.spacingSm + tokens.spacingXs),
            TroubleshootingList(steps: steps),
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
