/// How far the remote access setup sheet has got, as
/// `RemoteAccessSetupView` shows it.
enum RemoteAccessSetupStage {
  /// Explaining what remote access does, before anything is switched on.
  intro,

  /// The Quark is preparing its private connection: the request to turn
  /// remote access on is in flight.
  preparing,

  /// Remote access is on and the Quark is joining its private network.
  connecting,

  /// The Quark joined, and remote access works.
  done,
}
