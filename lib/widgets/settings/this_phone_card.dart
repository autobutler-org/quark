import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Remote access on this device, on the Network tab of Settings (#2876).
///
/// The same switch as the connection sheet. Turning it off asks how long,
/// and that pause stops only this device's node. The label says "this
/// phone" or "this computer" for the device the app is on (#3779). The
/// Network tab leaves this card out where there is no on-device node. The
/// switch reads off until this device has paired, and the line under it
/// says where setup stands: waiting on the Quark, what to do away from
/// home, or why it is not working (#3776). Turning it on checks again,
/// which pairs at home.
///
/// Key: `remote_access_on_this_phone`.
class ThisPhoneCard extends StatelessWidget {
  /// Creates the card over [connection], [ConnectionController.instance]
  /// unless a test passes its own.
  const ThisPhoneCard({super.key, this.connection});

  /// The controller the card reads and drives.
  final ConnectionController? connection;

  @override
  Widget build(BuildContext context) {
    final connection = this.connection ?? ConnectionController.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final error = connection.pairingError;
        final status = connection.phoneRemoteAccessDetail;
        final tokens = QuarkTokens.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            key: const ValueKey('remote_access_on_this_phone'),
            title: Text(remoteAccessOnThisDevice()),
            subtitle: error != null
                ? Text(error, style: TextStyle(color: tokens.error))
                : status != null
                ? Text(status)
                : null,
            value: connection.remoteAccessOnThisPhone,
            onChanged: (on) async {
              if (on) {
                await connection.resumeRemoteAccess();
                return;
              }
              final choice = await showDevicePauseChoice(context);
              if (!context.mounted || choice == null) return;
              await connection.pause(choice);
            },
          ),
        );
      },
    );
  }
}
