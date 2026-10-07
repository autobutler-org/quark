import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One key drawn as a key cap: a bordered chip holding [label].
///
/// It is decoration for the row that owns it, which reads the whole
/// combination aloud, so the cap itself is hidden from screen readers.
///
/// ```dart
/// SlideKeyCap(label: 'Ctrl');
/// ```
class SlideKeyCap extends StatelessWidget {
  /// A cap showing [label].
  const SlideKeyCap({required this.label, super.key});

  /// The legend printed on the cap.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 28),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm,
          vertical: tokens.spacingXs,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.input,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tokens.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
