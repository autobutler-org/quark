import 'package:flutter/material.dart';
import 'package:quark_formula/evaluation/evaluation.dart' show BuiltinFunction;

/// One built-in function in the autocomplete list: its signature over its one-line description, at least 48 pixels
/// tall. [selected] marks the row Tab or Enter would accept.
///
/// Key: `formula_suggestion_<NAME>`, e.g. `formula_suggestion_SUM`.
class FormulaSuggestionTile extends StatelessWidget {
  /// The function shown.
  final BuiltinFunction function;

  /// Whether it is the highlighted suggestion.
  final bool selected;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  const FormulaSuggestionTile({
    super.key,
    required this.function,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${function.signature}. ${function.description}',
      excludeSemantics: true,
      child: Tooltip(
        message: function.description,
        child: Material(
          color: selected ? cs.primaryContainer : Colors.transparent,
          child: InkWell(
            key: ValueKey('formula_suggestion_${function.name}'),
            canRequestFocus: false,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      function.signature,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? cs.onPrimaryContainer : null,
                      ),
                    ),
                    Text(
                      function.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
