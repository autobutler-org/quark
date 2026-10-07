import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// Why remote access could not connect and what to try, numbered, as
/// `RemoteAccessPanel` shows them while it is failing. The caller writes
/// [message] and [steps]; this lays them out.
///
/// Key prefixes: `remote_access_get_help` on the help button.
class RemoteAccessFailure extends StatelessWidget {
  /// Creates the failure explanation.
  const RemoteAccessFailure({
    required this.message,
    this.steps = const [],
    this.onGetHelp,
    super.key,
  });

  /// What went wrong, in the caller's words.
  final String message;

  /// What to try, in order. Each is numbered.
  final List<String> steps;

  /// Opens help. Null hides the button.
  final VoidCallback? onGetHelp;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onGetHelp = this.onGetHelp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingSm,
          children: [
            Icon(QuarkIcons.error_outline, size: 20, color: tokens.error),
            Expanded(child: Text(message)),
          ],
        ),
        for (final (index, step) in steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: tokens.spacingSm,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Text(step)),
            ],
          ),
        if (onGetHelp != null)
          TextButton.icon(
            key: const ValueKey('remote_access_get_help'),
            onPressed: onGetHelp,
            icon: const Icon(QuarkIcons.help_outline, size: 18),
            label: const Text('Get help'),
          ),
      ],
    );
  }
}
