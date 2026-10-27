import 'package:flutter/foundation.dart';

/// How far remote access has got on this phone for the active Quark (#3776).
enum ThisPhoneSetupState {
  /// This phone has no pairing with the Quark yet.
  notSetUp,

  /// Pairing is under way, or waiting on the Quark to finish connecting.
  settingUp,

  /// This phone is paired and its node started.
  ready,

  /// Setup failed; [ThisPhoneSetup.message] says why and what happens next.
  notWorking,
}

/// Remote access on this phone as its switch and card show it: a
/// [state] and, when there is something to say, a plain-language [message]
/// with the next step.
@immutable
class ThisPhoneSetup {
  /// Creates the setup state [state], explained by [message].
  const ThisPhoneSetup(this.state, [this.message]);

  /// Where setup stands.
  final ThisPhoneSetupState state;

  /// What the user reads under the switch, or null for nothing to add.
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is ThisPhoneSetup &&
      other.state == state &&
      other.message == message;

  @override
  int get hashCode => Object.hash(state, message);

  @override
  String toString() => 'ThisPhoneSetup($state, $message)';
}
