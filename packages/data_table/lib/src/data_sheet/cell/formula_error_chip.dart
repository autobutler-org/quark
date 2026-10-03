import 'package:flutter/material.dart';

/// A compact chip showing a formula error's [code] (`#DIV/0!`, `#REF!`), in the theme's error colors, with the
/// [message] saying why in its tooltip and its semantics label.
///
/// A grid cell shows it in place of an error result, and the formula bar beside the error's message.
///
/// ```dart
/// FormulaErrorChip(code: '#DIV/0!', message: 'Division by zero')
/// ```
class FormulaErrorChip extends StatelessWidget {
  /// The error code, e.g. `#NAME?`.
  final String code;

  /// Why the formula failed, e.g. `Unknown function TOTAL`.
  final String message;

  const FormulaErrorChip({
    super.key,
    required this.code,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    return Tooltip(
      message: '$code $message',
      child: Semantics(
        label: 'Error $code: $message',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
