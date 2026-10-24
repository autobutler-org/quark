import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Remote access on this phone, on the Network tab of Settings (#2876).
///
/// The same switch as the connection sheet. Turning it off asks how long,
/// and that pause stops only this phone's node.
///
/// Key: `remote_access_on_this_phone`.
class ThisPhoneCard extends StatelessWidget {
  /// Creates the card over [ConnectionController.instance].
  const ThisPhoneCard({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = ConnectionController.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final error = connection.pairingError;
        final tokens = QuarkTokens.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            key: const ValueKey('remote_access_on_this_phone'),
            title: const Text(remoteAccessOnThisPhone),
            subtitle: error == null
                ? null
                : Text(error, style: TextStyle(color: tokens.error)),
            value: !connection.remoteAccessPaused,
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
