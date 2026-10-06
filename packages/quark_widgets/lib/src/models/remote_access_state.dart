/// What remote access is doing on a Quark, as `RemoteAccessPanel` and
/// `ConnectionStatusView` show it.
enum RemoteAccessState {
  /// Switched off: the Quark can only be reached on the home network.
  off,

  /// Switched on, and the Quark is still joining its private network.
  connecting,

  /// Switched on, and the Quark can be reached away from home.
  on,

  /// Switched on, but the Quark could not join its private network.
  failing,
}
