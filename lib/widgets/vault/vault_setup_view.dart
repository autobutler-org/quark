import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The form that creates the vault by choosing and confirming its master password.
class VaultSetupView extends StatelessWidget {
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final String? error;
  final VoidCallback onCreate;

  const VaultSetupView({
    super.key,
    required this.passwordController,
    required this.confirmController,
    required this.error,
    required this.onCreate,
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
              const Icon(QuarkIcons.shield_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'Set up your vault',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a master password to encrypt your credentials. '
                'This cannot be recovered if forgotten.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCreate,
                  child: const Text('Create Vault'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
