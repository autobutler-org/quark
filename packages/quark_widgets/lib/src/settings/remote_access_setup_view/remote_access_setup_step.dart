import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../theme/quark_tokens.dart';

/// One row of the remote access setup checklist: a tick once [done], a
/// loader while [active], and an empty ring while it waits its turn.
class RemoteAccessSetupStep extends StatelessWidget {
  /// Creates the row.
  const RemoteAccessSetupStep({
    required this.label,
    this.done = false,
    this.active = false,
    super.key,
  });

  /// What this step does, in a few words.
  final String label;

  /// Whether the step has finished.
  final bool done;

  /// Whether the step is under way. Ignored once [done].
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final Widget mark;
    if (done) {
      mark = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: tokens.success,
          shape: BoxShape.circle,
        ),
        child: Icon(QuarkIcons.check, size: 16, color: tokens.background),
      );
    } else if (active) {
      mark = const SizedBox(
        width: 28,
        height: 28,
        child: QuarkLoader(size: 28),
      );
    } else {
      mark = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.border, width: 2),
        ),
      );
    }
    return Semantics(
      label: '$label, ${done ? 'done' : (active ? 'in progress' : 'waiting')}',
      excludeSemantics: true,
      child: Row(
        spacing: tokens.spacingMd,
        children: [
          mark,
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: active && !done ? FontWeight.w600 : null,
                color: done || active ? null : tokens.secondaryForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
