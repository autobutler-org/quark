import 'package:flutter/material.dart';
import 'package:quark_formula/evaluation/evaluation.dart' show BuiltinFunction;

import 'formula_suggestion_tile.dart';

/// The popover list of built-in functions matching the name being typed, one [FormulaSuggestionTile] each, scrolling
/// when they outgrow the space it is given.
///
/// Key: `formula_suggestions` on the list; its rows are `formula_suggestion_<NAME>`.
class FormulaSuggestionList extends StatelessWidget {
  /// The matching functions, in the order shown.
  final List<BuiltinFunction> functions;

  /// The index of the highlighted function.
  final int selectedIndex;

  /// The key given to the highlighted row, so the caller can scroll it into view.
  final Key? selectedKey;

  /// Called with the function the user taps.
  final ValueChanged<BuiltinFunction> onSelected;

  const FormulaSuggestionList({
    super.key,
    required this.functions,
    required this.selectedIndex,
    required this.onSelected,
    this.selectedKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Function suggestions',
      container: true,
      child: Material(
        key: const ValueKey('formula_suggestions'),
        elevation: 4,
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < functions.length; i++)
                KeyedSubtree(
                  key: i == selectedIndex ? selectedKey : null,
                  child: FormulaSuggestionTile(
                    function: functions[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(functions[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
