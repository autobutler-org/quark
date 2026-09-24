import 'package:flutter/material.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
import 'package:quark/widgets/settings/code_block.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Remote access card on the Network tab of Settings: whether the Quark
/// is on its Tailscale tunnel, its remote address, and, for an admin, the
/// switch to turn it on or off.
///
/// Keys: `settings_remote_access_failing`,
/// `settings_remote_access_connecting`, `remote_access_coming_soon`.
class RemoteAccessCard extends StatelessWidget {
  /// Creates the card.
  const RemoteAccessCard({
    required this.status,
    required this.isLoading,
    required this.isToggling,
    required this.error,
    required this.disconnected,
    required this.isAdmin,
    required this.onRetry,
    required this.onEnable,
    required this.onDisable,
    super.key,
  });

  /// The last status read, or null before the first.
  final RemoteAccessStatus? status;

  /// Whether the status is being read.
  final bool isLoading;

  /// Whether an enable or disable is in flight.
  final bool isToggling;

  /// Why the status could not be read, or null.
  final String? error;

  /// Whether the Quark is unreachable, which the page banner explains, so
  /// the card says so in a word instead of repeating [error].
  final bool disconnected;

  /// Whether the user may turn remote access on or off.
  final bool isAdmin;

  /// Reads the status again.
  final VoidCallback onRetry;

  /// Turns remote access on.
  final VoidCallback onEnable;

  /// Turns remote access off.
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = this.status;
    const spinner = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : error != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    disconnected ? quarkDisconnectedShort : error!,
                    style: TextStyle(color: colors.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(QuarkIcons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              )
            : status?.enabled == true
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // On is the Quark's setting; on the tailnet is a separate
                  // fact that can lag it or never arrive.
                  if (status!.error != null)
                    Row(
                      children: [
                        Icon(
                          QuarkIcons.error_outline,
                          size: 16,
                          color: colors.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            Errors.remoteAccessFailing,
                            key: const ValueKey(
                              'settings_remote_access_failing',
                            ),
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ],
                    )
                  else if (!status.connected)
                    const Row(
                      children: [
                        Icon(QuarkIcons.cloud_sync_outlined, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Connecting…',
                          key: ValueKey('settings_remote_access_connecting'),
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(
                          QuarkIcons.cloud_done_outlined,
                          size: 16,
                          color: Colors.green,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Connected via Tailscale',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  if (status.remoteUrl != null &&
                      status.remoteUrl!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    CodeBlock(text: status.remoteUrl!),
                  ],
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isToggling ? null : onDisable,
                      icon: isToggling
                          ? spinner
                          : const Icon(QuarkIcons.link_off, size: 16),
                      label: const Text('Disable'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Access your quark from anywhere using Tailscale.',
                  ),
                  if (!RemoteAccessConfig.enableAvailable) ...[
                    const SizedBox(height: 8),
                    Row(
                      key: const ValueKey('remote_access_coming_soon'),
                      children: [
                        Chip(
                          label: const Text('Coming soon'),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(color: colors.outlineVariant),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Not available yet. Your Quark is reachable on '
                            'your home network in the meantime.',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (isAdmin) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isToggling ? null : onEnable,
                      icon: isToggling
                          ? spinner
                          : const Icon(QuarkIcons.vpn_key_outlined, size: 16),
                      label: const Text('Enable remote access'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
