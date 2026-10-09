import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_item.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The chart group's "Series colors" button (#1160): a menu with a
/// submenu per series — per slice, in a pie — holding a
/// [SlideColorPalette], theme colors first, and [reset], which gives every
/// series back the theme's accents. Disabled while [reset] is.
///
/// Key prefixes: `slide_chart_colors` on the button, `<color key>_menu` on
/// each series' submenu (`slide_chart_color_<index>_menu`), and the
/// palettes' and [reset]'s own.
class SlideChartColorsMenuButton extends StatelessWidget {
  /// A button for the series [colors].
  const SlideChartColorsMenuButton({
    required this.colors,
    required this.reset,
    super.key,
  });

  /// One color control per series.
  final List<SlideColorChoice> colors;

  /// Back to the theme's colors.
  final SlideToolbarChoice reset;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final choice in colors)
        QuarkSubmenuButton(
          key: ValueKey('${choice.key}_menu'),
          leadingIcon: Icon(choice.icon),
          menuChildren: [SlideColorPalette(choice: choice)],
          child: Text(choice.label),
        ),
      SlideChoiceMenuItem(choice: reset),
    ],
    builder: (context, menu, _) => QuarkBarIconButton(
      key: const ValueKey('slide_chart_colors'),
      icon: QuarkIcons.chart_colors,
      tooltip: 'Series colors',
      onPressed: reset.onSelected == null
          ? null
          : () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
