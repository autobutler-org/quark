import 'package:flutter/foundation.dart';

/// The address an Android emulator reaches the developer's machine on.
///
/// Inside the emulator `localhost` is the emulator itself, so a Quark running
/// on the machine that hosts it answers here instead.
const String emulatorHostAlias = '10.0.2.2';

/// Whether [host], a bare [Uri.host], names the machine the app itself runs
/// on.
bool isLoopbackHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

/// What the Add Quark forms say under an [address] that cannot be right on an
/// Android emulator (#2070), or null when there is nothing to say.
///
/// [address] is a URL, as `normalizeHostAddress` returns it. Only a loopback
/// address on Android gets the hint: every other platform's `localhost` is
/// the machine the Quark runs on, and the app cannot tell an emulator from a
/// phone, so the sentence names the emulator rather than assuming one.
String? emulatorLoopbackHint(String address) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  final host = Uri.tryParse(address)?.host ?? '';
  if (!isLoopbackHost(host)) return null;
  return 'On an Android emulator, use $emulatorHostAlias instead of '
      'localhost to reach a Quark running on your computer.';
}
