/// Tuning for the remote access section of Settings (#1876).
abstract final class RemoteAccessConfig {
  /// Whether a user can turn remote access on from Settings.
  ///
  /// False: the enable path cannot succeed today — the app posts an empty
  /// body and the endpoint refuses it for want of an auth key (#1815) — and
  /// an Enable button that always fails reads as a broken product rather than
  /// a feature that has not shipped (#2036). The soft-launch docs already
  /// describe remote access as coming later; this makes Settings say the
  /// same thing.
  ///
  /// Flip it back to true with the wiring in #1815, and the button returns
  /// exactly as it was. A Quark that is already connected still shows its
  /// address and its Disable button either way.
  static const bool enableAvailable = false;

  /// How often Settings re-reads the status while remote access is on but the
  /// Quark has not joined the tailnet yet.
  ///
  /// Joining takes a few seconds once a key is provisioned, so a short interval
  /// means "Connecting…" turns into the remote URL without a reload. The poll
  /// only runs while the page is open and stops once the Quark is connected, so
  /// its cost is a handful of small GETs.
  static const Duration statusPollInterval = Duration(seconds: 3);
}
