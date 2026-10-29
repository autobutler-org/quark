import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/router.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/widgets/layout/connection_sheet.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The app bar's connection indicator, which opens [ConnectionSheet] when
/// tapped (#2857), so how the app reaches its Quark is two taps from any
/// page.
///
/// It sits in every main page's bar, below the navigator, so it opens the
/// sheet from its own context; the app root above the navigator only knows
/// how to [onNavigate]. While remote access is paused on this phone the
/// pill reads Paused (#2876).
///
/// Keys: `connection_indicator`, and those of [ConnectionStatusView].
class ConnectionSheetButton extends StatelessWidget {
  /// Creates the indicator for [mode].
  const ConnectionSheetButton({
    required this.mode,
    required this.onNavigate,
    this.readRemoteAccess = RemoteAccessService.getStatus,
    this.paused = false,
    this.thisPhoneOn = true,
    this.pairingError,
    this.phoneStatus,
    this.offlineReason,
    this.onPause,
    this.onResume,
    super.key,
  });

  /// How the app is reaching its Quark.
  final ConnectionMode mode;

  /// Opens a route. The root passes the router's own `go`.
  final ValueChanged<String> onNavigate;

  /// Reads the Quark's remote access status for the sheet. A test passes a
  /// fake.
  final Future<RemoteAccessStatus> Function() readRemoteAccess;

  /// Whether remote access is paused on this phone. The pill then reads
  /// Paused.
  final bool paused;

  /// Whether the sheet's switch reads on. A phone that never paired reads
  /// off even when it is not paused.
  final bool thisPhoneOn;

  /// Why automatic pairing failed, in [Errors]' words, or null.
  final String? pairingError;

  /// Where this phone's remote access setup stands, in words, or null.
  final String? phoneStatus;

  /// Why the Quark is out of reach, when the app knows, or null.
  final String? offlineReason;

  /// Pauses remote access on this phone. Null hides the switch.
  final Future<void> Function(DevicePauseChoice choice)? onPause;

  /// Turns remote access back on for this phone.
  final Future<void> Function()? onResume;

  @override
  Widget build(BuildContext context) {
    final onPause = this.onPause;
    final onResume = this.onResume;
    void open() => showQuarkSheet<void>(
      context,
      title: 'Connection',
      builder: (sheetContext) => ConnectionSheet(
        mode: mode,
        readRemoteAccess: readRemoteAccess,
        remoteAccessOnThisPhone: thisPhoneOn && !paused,
        pairingError: pairingError,
        phoneStatus: phoneStatus,
        offlineReason: offlineReason,
        onRemoteAccessChanged: onPause == null
            ? null
            : (on) async {
                if (on) {
                  await onResume?.call();
                  return;
                }
                final choice = await showDevicePauseChoice(context);
                if (!context.mounted || choice == null) return;
                await onPause(choice);
              },
        onOpenSettings: () {
          Navigator.of(sheetContext).pop();
          onNavigate(AppRoutes.settingsTab(SettingsTab.network));
        },
      ),
    );

    if (paused) {
      return QuarkBarChip(
        key: const ValueKey('connection_indicator'),
        icon: QuarkIcons.pause,
        label: 'Paused',
        tooltip: 'Paused',
        keepLabel: true,
        onPressed: open,
      );
    }
    return ConnectionIndicator(
      mode: mode,
      label: ConnectionSheet.labelFor(mode),
      onTap: open,
    );
  }
}
