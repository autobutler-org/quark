/// Tuning for the remote access section of Settings (#1876).
abstract final class RemoteAccessConfig {
  /// How often Settings re-reads the status while remote access is on but the
  /// Quark has not joined the tailnet yet.
  ///
  /// Joining takes a few seconds once a key is provisioned, so a short interval
  /// means "Connecting…" turns into the remote URL without a reload. The poll
  /// only runs while the page is open and stops once the Quark is connected, so
  /// its cost is a handful of small GETs.
  static const Duration statusPollInterval = Duration(seconds: 3);
}
