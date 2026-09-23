import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_icons/quark_icons.dart';

/// The form that unlocks the vault with its master password, saying why it is locked.
class VaultUnlockView extends StatelessWidget {
  final TextEditingController passwordController;
  final String lockReason;
  final String? error;
  final bool unlocking;
  final VoidCallback onUnlock;

  const VaultUnlockView({
    super.key,
    required this.passwordController,
    required this.lockReason,
    required this.error,
    required this.unlocking,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(QuarkIcons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                'Vault is locked',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (lockReason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  lockReason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Master password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onUnlock(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: unlocking ? null : onUnlock,
                  child: unlocking
                      ? const QuarkLoader(size: 20)
                      : const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
