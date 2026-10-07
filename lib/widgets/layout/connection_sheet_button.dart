import 'package:flutter/material.dart';
import 'package:quark/router.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/widgets/layout/connection_sheet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The app bar's connection indicator, which opens [ConnectionSheet] when
/// tapped (#2857), so how the app reaches its Quark is two taps from any
/// page.
///
/// It sits in every main page's bar, below the navigator, so it opens the
/// sheet from its own context; the app root above the navigator only knows
/// how to [onNavigate].
///
/// Keys: `connection_indicator`, and those of [ConnectionStatusView].
class ConnectionSheetButton extends StatelessWidget {
  /// Creates the indicator for [mode].
  const ConnectionSheetButton({
    required this.mode,
    required this.onNavigate,
    this.readRemoteAccess = RemoteAccessService.getStatus,
    super.key,
  });

  /// How the app is reaching its Quark.
  final ConnectionMode mode;

  /// Opens a route. The root passes the router's own `go`.
  final ValueChanged<String> onNavigate;

  /// Reads the Quark's remote access status for the sheet. A test passes a
  /// fake.
  final Future<RemoteAccessStatus> Function() readRemoteAccess;

  @override
  Widget build(BuildContext context) {
    return ConnectionIndicator(
      mode: mode,
      label: ConnectionSheet.labelFor(mode),
      onTap: () => showQuarkSheet<void>(
        context,
        title: 'Connection',
        builder: (sheetContext) => ConnectionSheet(
          mode: mode,
          readRemoteAccess: readRemoteAccess,
          onOpenSettings: () {
            Navigator.of(sheetContext).pop();
            onNavigate(AppRoutes.settingsTab(SettingsTab.network));
          },
        ),
      ),
    );
  }
}
