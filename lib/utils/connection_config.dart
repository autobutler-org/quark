/// Timings for choosing between a Quark's home and remote-access address
/// (#1880), read by `ConnectionController`.
abstract final class ConnectionConfig {
  /// How long the home address gets to answer before the app tries the
  /// remote one. Short: on the home network a Quark answers in milliseconds,
  /// and every second here is a second the app looks stuck away from home.
  static const Duration lanProbeTimeout = Duration(seconds: 2);

  /// How long the remote-access address gets to answer. Longer than the LAN
  /// probe, since it crosses the internet and a relay.
  static const Duration remoteProbeTimeout = Duration(seconds: 5);

  /// How often the app checks again while it has a working address.
  ///
  /// On the remote address this is how soon it moves back to the home one
  /// after the phone rejoins the home network. On the home address it is how
  /// soon it notices having left, and it also re-reads the Quark's
  /// remote-access address so a change in Settings reaches this list.
  static const Duration recheckInterval = Duration(seconds: 30);

  /// The first wait before trying again after neither address answered.
  static const Duration offlineBackoffInitial = Duration(seconds: 2);

  /// The longest wait between tries while offline. The backoff doubles from
  /// [offlineBackoffInitial] up to this.
  static const Duration offlineBackoffMax = Duration(minutes: 1);
}
