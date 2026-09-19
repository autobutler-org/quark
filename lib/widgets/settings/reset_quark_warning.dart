import 'package:flutter/material.dart';

/// A warning panel inside the reset dialog.
///
/// Two of these can appear, for the two ways a reset surprises someone: a
/// selection that leaves data on the Quark, and one that reaches onto a drive
/// the user plugged in (#2052). They look the same on purpose — the dialog
/// decides which is on screen, and the copy is what differs.
class ResetQuarkWarning extends StatelessWidget {
  /// Creates a warning panel reading [message].
  const ResetQuarkWarning({required this.message, super.key});

  /// The sentence to show. Always a full sentence a user can act on; the
  /// dialog owns the strings.
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
