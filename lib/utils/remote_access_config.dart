/// Tuning for the remote access section of Settings (#1876).
abstract final class RemoteAccessConfig {
  /// Whether an admin can turn remote access on from Settings.
  ///
  /// True: the Quark fetches its own key from the provisioning service and
  /// enrolls as its own Headscale household (#2358), so the empty-body enable
  /// the app posts succeeds. Setting it to false shows **Coming soon** in place
  /// of the button (#2036); a Quark that is already connected still shows its
  /// address and its Disable button either way.
  static const bool enableAvailable = true;

  /// How often Settings re-reads the status while remote access is on but the
  /// Quark has not joined the tailnet yet.
  ///
  /// Joining takes a few seconds once a key is provisioned, so a short interval
  /// means "Connecting…" turns into the remote URL without a reload. The poll
  /// only runs while the page is open and stops once the Quark is connected, so
  /// its cost is a handful of small GETs.
  static const Duration statusPollInterval = Duration(seconds: 3);
}
