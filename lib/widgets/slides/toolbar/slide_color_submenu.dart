import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A submenu named after [choice] holding its [SlideColorPalette]: a color
/// in the phone "Format" menu, and a series in "Series colors".
///
/// Key prefixes: `<choice key>_menu` on the submenu, and the palette's.
class SlideColorSubmenu extends StatelessWidget {
  /// The submenu for [choice].
  const SlideColorSubmenu({required this.choice, super.key});

  /// The color it sets.
  final SlideColorChoice choice;

  @override
  Widget build(BuildContext context) => QuarkSubmenuButton(
    key: ValueKey('${choice.key}_menu'),
    leadingIcon: Icon(choice.icon),
    menuChildren: [SlideColorPalette(choice: choice)],
    child: Text(choice.label),
  );
}
