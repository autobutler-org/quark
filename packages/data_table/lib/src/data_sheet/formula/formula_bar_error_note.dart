import 'package:flutter/material.dart';

import '../cell/formula_error_chip.dart';

/// The line under the formula bar when the selected cell's formula failed: the error's [code] in a
/// [FormulaErrorChip] beside the full [message], so the reason is readable without hovering.
///
/// Key: `data_sheet_formula_error`.
class FormulaBarErrorNote extends StatelessWidget {
  /// The error code, e.g. `#REF!`.
  final String code;

  /// Why the formula failed.
  final String message;

  const FormulaBarErrorNote({
    super.key,
    required this.code,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('data_sheet_formula_error'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          FormulaErrorChip(code: code, message: message),
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
