import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/emulator_loopback.dart';

/// The line under an Add Quark address field that says to type `10.0.2.2`
/// instead of `localhost` on an Android emulator (#2070).
///
/// It listens to the field's [controller] and takes no space until
/// [emulatorLoopbackHint] has something to say about what is typed. It is its
/// own line rather than the field's helper text because a failed connection
/// replaces the helper, and that is the moment the hint is needed.
///
/// Key: `emulator_loopback_hint` on the text.
class EmulatorLoopbackHint extends StatelessWidget {
  const EmulatorLoopbackHint({super.key, required this.controller});

  /// The address field's controller.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hint = emulatorLoopbackHint(normalizeHostAddress(value.text));
        if (hint == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            hint,
            key: const ValueKey('emulator_loopback_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
