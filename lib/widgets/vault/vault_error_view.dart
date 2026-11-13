import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    return EmptyStateWidget(
      icon: QuarkIcons.error_outline,
      headline: message,
      action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}
