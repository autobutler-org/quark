import 'package:flutter/material.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/models/this_phone_setup.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Remote access on this phone, on the Network tab of Settings (#2876).
///
/// The same switch as the connection sheet. Turning it off asks how long,
/// and that pause stops only this phone's node. The switch is on only once
/// this phone has started setting up, and the line under it says where
/// setup stands: not set up yet, setting up, ready, or not working and why
/// (#3776). Turning it on while not set up runs a check, which pairs when
/// the phone is home.
///
/// Key: `remote_access_on_this_phone`.
class ThisPhoneCard extends StatelessWidget {
  /// Creates the card over [controller], or [ConnectionController.instance].
  const ThisPhoneCard({this.controller, super.key});

  /// Where the state comes from. Null uses [ConnectionController.instance].
  final ConnectionController? controller;

  /// What the card says for [state] when [ThisPhoneSetup.message] is null.
  static String labelFor(ThisPhoneSetupState state) => switch (state) {
    ThisPhoneSetupState.notSetUp => 'Not set up yet.',
    ThisPhoneSetupState.settingUp => ConnectionController.settingUpNow,
    ThisPhoneSetupState.ready => ConnectionController.readyAway,
    ThisPhoneSetupState.notWorking => 'Remote access is not working.',
  };

  @override
  Widget build(BuildContext context) {
    final connection = controller ?? ConnectionController.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final setup = connection.setup;
        final paused = connection.remoteAccessPaused;
        final tokens = QuarkTokens.of(context);
        final failed = setup.state == ThisPhoneSetupState.notWorking;
        return Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            key: const ValueKey('remote_access_on_this_phone'),
            title: const Text(remoteAccessOnThisPhone),
            subtitle: paused
                ? null
                : Text(
                    setup.message ?? labelFor(setup.state),
                    key: const ValueKey('remote_access_on_this_phone_status'),
                    style: failed ? TextStyle(color: tokens.error) : null,
                  ),
            value: !paused && setup.state != ThisPhoneSetupState.notSetUp,
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
