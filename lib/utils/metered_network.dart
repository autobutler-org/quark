import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's own channel to `MainActivity` and `AppDelegate`, which say
/// whether the network in use may cost the user money (#4222).
const meteredNetworkChannel = MethodChannel('org.autobutler.quark/network');

/// Whether the device is on a network that may cost the user money: mobile
/// data, a shared phone connection, or iOS Low Data Mode. A kept album
/// downloads only when this is false, unless the person allowed mobile data.
///
/// No network at all also answers true, so nothing starts that cannot finish.
/// A phone whose platform does not answer is treated as metered, the safe
/// guess; a desktop, which has no such channel and is on Wi-Fi or a cable,
/// as not.
Future<bool> isOnMeteredNetwork() async {
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!phone) return false;
  try {
    return await meteredNetworkChannel.invokeMethod<bool>('isMetered') ?? true;
  } on PlatformException {
    return true;
  } on MissingPluginException {
    return true;
  }
}
