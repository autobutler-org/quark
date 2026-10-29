import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The switch that pauses remote access on this phone only (#2876).
const String remoteAccessOnThisPhone = 'Remote access on this phone';

/// The same switch once a desktop can run a node (#2877).
const String remoteAccessOnThisComputer = 'Remote access on this computer';

/// What the Network tab says where this build has no on-device node (#3779).
///
/// Desktop cannot run remote access yet (#2877). At home the app still
/// talks to the Quark on the local network.
const String desktopRemoteAccessUnavailable =
    "Remote access isn't available in the desktop app yet. "
    'At home, Quark works as usual.';

/// Whether [platform] is a phone. Tests pass a platform; otherwise this is
/// the one the app is running on. Flutter tests report Android.
bool _isPhonePlatform(TargetPlatform? platform) {
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS;
}

/// The Network tab's heading for this device's own remote access (#3779).
///
/// "This phone" on a phone, "This computer" on desktop, so the section is
/// already named for a desktop node (#2877).
String thisDeviceRemoteAccessHeading([TargetPlatform? platform]) =>
    _isPhonePlatform(platform) ? 'This phone' : 'This computer';

/// The switch label for this device's own remote access.
String remoteAccessOnThisDevice([TargetPlatform? platform]) =>
    _isPhonePlatform(platform)
    ? remoteAccessOnThisPhone
    : remoteAccessOnThisComputer;

/// How long a timed pause lasts, as the choice itself says it.
const String pauseForAnHour = 'For 1 hour';

/// Pause until the next time this phone reaches the Quark at home.
const String pauseUntilHome = 'Until I\'m back on home Wi\u2011Fi';

/// Pause until the person turns remote access back on.
const String pauseUntilManual = 'Until I turn it back on';

/// The banner sentence for [choice]: until when this phone stays paused.
String devicePauseBanner(DevicePauseChoice choice) => switch (choice) {
  DevicePauseChoice.hour => 'Paused for 1 hour.',
  DevicePauseChoice.untilHome =>
    'Paused until you\'re back on home Wi\u2011Fi.',
  DevicePauseChoice.untilManual => 'Paused until you turn it back on.',
};

/// Asks how long to pause remote access on this phone.
///
/// Null means they left it on: Cancel, or a tap outside the dialog.
/// Keys: `pause_choice_hour`, `pause_choice_home`, `pause_choice_manual`.
Future<DevicePauseChoice?> showDevicePauseChoice(BuildContext context) {
  return showDialog<DevicePauseChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(remoteAccessOnThisDevice()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (key, label, choice) in const [
            ('pause_choice_hour', pauseForAnHour, DevicePauseChoice.hour),
            ('pause_choice_home', pauseUntilHome, DevicePauseChoice.untilHome),
            (
              'pause_choice_manual',
              pauseUntilManual,
              DevicePauseChoice.untilManual,
            ),
          ])
            ListTile(
              key: ValueKey(key),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(choice),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// A strip under the app bar while remote access is paused on this phone.
///
/// It says until when, and **Turn on** ends the pause. It takes no space
/// when this phone is not paused.
///
/// Keys: `remote_access_pause_banner`, `remote_access_pause_turn_on`.
class RemoteAccessPauseBanner extends StatelessWidget {
  /// Creates the banner for [controller], or the app's controller.
  const RemoteAccessPauseBanner({this.controller, super.key});

  /// Where the pause comes from. Null uses [ConnectionController.instance].
  final ConnectionController? controller;

  @override
  Widget build(BuildContext context) {
    final connection = controller ?? ConnectionController.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final choice = connection.pauseChoice;
        if (choice == null) return const SizedBox.shrink();
        final tokens = QuarkTokens.of(context);
        return Material(
          key: const ValueKey('remote_access_pause_banner'),
          color: tokens.warning.withValues(alpha: 0.15),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
            child: Row(
              children: [
                Icon(QuarkIcons.pause, size: 18, color: tokens.warning),
                SizedBox(width: tokens.spacingSm),
                Expanded(child: Text(devicePauseBanner(choice))),
                TextButton(
                  key: const ValueKey('remote_access_pause_turn_on'),
                  onPressed: () => unawaited(connection.resumeRemoteAccess()),
                  child: const Text('Turn on'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
