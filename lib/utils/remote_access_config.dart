import 'package:flutter/foundation.dart';

/// Tuning for the remote access section of Settings (#1876).
abstract final class RemoteAccessConfig {
  /// Whether an admin can set remote access up from Settings.
  ///
  /// The Quark enrolls itself (#2358), so turning it on works, but until the
  /// app runs its own tunnel (#2876, on #1881) no phone can use it without
  /// installing Tailscale, which our users should never be asked to do. So
  /// release builds say **Coming soon** in place of the set-up button
  /// (#2857), and debug and profile builds offer it for testing. A Quark that
  /// is already on still shows its state and its switch either way.
  static const bool enableAvailable = !kReleaseMode;

  /// How often Settings re-reads the status while remote access is on but the
  /// Quark has not joined the tailnet yet.
  ///
  /// Joining takes a few seconds once a key is provisioned, so a short interval
  /// means "Connecting…" turns into the remote URL without a reload. The poll
  /// only runs while the page is open and stops once the Quark is connected, so
  /// its cost is a handful of small GETs.
  static const Duration statusPollInterval = Duration(seconds: 3);
}
