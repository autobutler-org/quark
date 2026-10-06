import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/connection_mode.dart';
import '../models/remote_access_state.dart';
import '../theme/quark_tokens.dart';
import 'connection_indicator.dart';

/// What `ConnectionIndicator` means, spelled out: the content of the sheet a
/// tap on the indicator opens. It says how the app is reaching its Quark
/// right now, in the caller's [label] and [detail], and links to the Quark's
/// remote access settings with [remoteAccess] as a word.
///
/// Key prefixes: `connection_sheet_status` on the header,
/// `connection_sheet_settings` on the settings row.
///
/// ```dart
/// ConnectionStatusView(
///   mode: ConnectionMode.remote,
///   label: 'Connected through remote access',
///   detail: "You're away from home, so the app reaches your Quark through "
///       'remote access.',
///   remoteAccess: RemoteAccessState.on,
///   onOpenSettings: () => context.go('/settings/network'),
/// );
/// ```
class ConnectionStatusView extends StatelessWidget {
  /// Creates the view for [mode].
  const ConnectionStatusView({
    required this.mode,
    required this.label,
    required this.detail,
    this.remoteAccess,
    this.onOpenSettings,
    super.key,
  });

  /// How the app is reaching its Quark.
  final ConnectionMode mode;

  /// [mode] in a few words, the same ones the indicator's tooltip uses.
  final String label;

  /// What [mode] means for the reader, in a sentence.
  final String detail;

  /// What the Quark's remote access is doing, or null when it is not known.
  final RemoteAccessState? remoteAccess;

  /// Opens the Quark's remote access settings. Null hides the row.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (icon, color) = ConnectionIndicator.glyphFor(mode, tokens);
    final onOpenSettings = this.onOpenSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: tokens.spacingMd,
      children: [
        Row(
          key: const ValueKey('connection_sheet_status'),
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingMd,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(tokens.radiusLg),
              ),
              child: Icon(icon, color: color),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: tokens.spacingXs,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(color: tokens.secondaryForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (onOpenSettings != null)
          ListTile(
            key: const ValueKey('connection_sheet_settings'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(QuarkIcons.devices),
            title: const Text('Your Quark'),
            subtitle: Text(switch (remoteAccess) {
              null => 'Remote access settings',
              RemoteAccessState.off => 'Remote access is off',
              RemoteAccessState.connecting => 'Remote access is connecting',
              RemoteAccessState.on => 'Remote access is on',
              RemoteAccessState.failing => "Remote access couldn't connect",
            }),
            trailing: const Icon(QuarkIcons.chevron_right),
            onTap: onOpenSettings,
          ),
      ],
    );
  }
}
