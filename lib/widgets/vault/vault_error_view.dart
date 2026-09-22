import 'package:flutter/material.dart';

/// What the Vault page shows when it cannot load, with a way to retry.
class VaultErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const VaultErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
