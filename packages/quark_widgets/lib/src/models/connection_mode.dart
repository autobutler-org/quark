/// Which address the app is reaching its Quark on, as `ConnectionIndicator`
/// shows it.
enum ConnectionMode {
  /// The Quark's own address on the home network answered.
  local,

  /// The home address did not answer, so requests go to the Quark's
  /// remote-access address instead.
  remote,

  /// Neither address answered.
  offline,
}
