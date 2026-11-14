import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// The one stepper: a button down, the value in a 36px slot, a button up,
/// and an optional leading label.
///
/// The stepper owns the layout and the value's look. The caller owns the
/// nouns and which actions exist: it builds the two buttons (usually
/// `QuarkBarIconButton`s, with its own icons, tooltips and keys) and passes
/// null `onPressed` on a button that is at its limit.
///
/// With a [label] the stepper fills its row, the label taking the room left
/// of the buttons; without one it is as wide as its three parts.
///
/// Key prefixes: none of its own. The caller's [valueKey] sits on the value
/// text, and the buttons carry the caller's keys.
///
/// ```dart
/// QuarkStepper(
///   label: 'Rows',
///   value: '$rows',
///   semanticsLabel: 'Rows $rows',
///   valueKey: const ValueKey('table_rows_value'),
///   decrease: QuarkBarIconButton(
///     key: const ValueKey('table_rows_less'),
///     icon: QuarkIcons.remove,
///     tooltip: 'Fewer rows',
///     onPressed: rows > 1 ? () => setRows(rows - 1) : null,
///   ),
///   increase: QuarkBarIconButton(
///     key: const ValueKey('table_rows_more'),
///     icon: QuarkIcons.add,
///     tooltip: 'More rows',
///     onPressed: () => setRows(rows + 1),
///   ),
/// );
/// ```
class QuarkStepper extends StatelessWidget {
  /// A stepper reading [value] between [decrease] and [increase].
  const QuarkStepper({
    required this.value,
    required this.semanticsLabel,
    required this.decrease,
    required this.increase,
    this.label,
    this.valueKey,
    super.key,
  });

  /// The width the value never shrinks below, so the buttons stay put as
  /// the value changes length.
  static const double valueMinWidth = 36;

  /// The value as shown, such as "3" or "24". May be empty, as for a mixed
  /// selection.
  final String value;

  /// What a screen reader hears for the value, such as "Rows 3".
  final String semanticsLabel;

  /// The button that steps down. The caller picks its icon, tooltip and key.
  final Widget decrease;

  /// The button that steps up. The caller picks its icon, tooltip and key.
  final Widget increase;

  /// What it counts, such as "Rows", shown before the buttons. Null for a
  /// stepper that sits in a toolbar.
  final String? label;

  /// The key on the value text, for tests and Probe scripts.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = Theme.of(context).textTheme;
    final label = this.label;
    return Row(
      mainAxisSize: label == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (label != null)
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: tokens.foreground),
            ),
          ),
        decrease,
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: valueMinWidth),
          child: Semantics(
            label: semanticsLabel,
            excludeSemantics: true,
            child: Text(
              value,
              key: valueKey,
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(color: tokens.foreground),
            ),
          ),
        ),
        increase,
      ],
    );
  }
}
