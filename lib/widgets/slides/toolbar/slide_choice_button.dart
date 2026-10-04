import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slide toolbar choice as a bar button: its glyph, its label as the
/// tooltip, lit while it is on, disabled while it does not apply.
///
/// Key prefixes: the choice's own `key`.
class SlideChoiceButton extends StatelessWidget {
  /// Draws [choice].
  const SlideChoiceButton({required this.choice, super.key});

  /// The control.
  final SlideToolbarChoice choice;

  @override
  Widget build(BuildContext context) => QuarkBarIconButton(
    key: ValueKey(choice.key),
    icon: choice.icon!,
    tooltip: choice.label,
    selected: choice.selected,
    onPressed: choice.onSelected,
  );
}
