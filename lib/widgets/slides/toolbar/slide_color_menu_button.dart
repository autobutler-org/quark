import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slide toolbar button that opens a [SlideColorPalette] for [choice]:
/// text color, fill, outline color. Disabled while the color does not
/// apply to the selection.
///
/// Key prefixes: [SlideColorChoice.key] on the button, and the palette's.
class SlideColorMenuButton extends StatelessWidget {
  /// A button opening the palette for [choice].
  const SlideColorMenuButton({required this.choice, super.key});

  /// The color control.
  final SlideColorChoice choice;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [SlideColorPalette(choice: choice)],
    builder: (context, menu, _) => QuarkBarIconButton(
      key: ValueKey(choice.key),
      icon: choice.icon,
      tooltip: choice.label,
      onPressed: choice.onChanged == null
          ? null
          : () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
