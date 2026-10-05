/// Tuning for how the app follows the Quark's event socket: how long the Files
/// page waits out a burst of events, and how reconnects back off (#2763).
abstract final class EventsConfig {
  /// How long the Files page waits after the last event in its folder before
  /// it refreshes, so a burst (500 files landing) costs one refresh.
  static const Duration refreshQuiet = Duration(seconds: 2);

  /// The longest a steady stream of events can hold that refresh back.
  static const Duration refreshMaxWait = Duration(seconds: 10);

  /// The reconnect delay after the first failure, before jitter.
  static const Duration reconnectBase = Duration(seconds: 1);

  /// The most the reconnect delay grows to, before jitter.
  static const Duration reconnectCap = Duration(seconds: 30);

  /// How far each reconnect delay is spread either way, as a fraction of it,
  /// so apps that lost the Quark together do not come back together.
  static const double reconnectJitter = 0.5;
}
