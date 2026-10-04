import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The vault's own USB drive is unplugged from a Quark the app can reach
/// perfectly well — distinct from the Quark itself being unreachable (#1637).
class VaultDeviceDisconnectedView extends StatelessWidget {
  final VoidCallback onRetry;

  const VaultDeviceDisconnectedView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  QuarkIcons.usb_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Vault device disconnected',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'The external storage device containing your vault is not connected. '
                  'Please reconnect the device to access your vault.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(QuarkIcons.refresh),
                  label: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
