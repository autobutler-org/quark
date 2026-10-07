import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_item.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The phone slide toolbar's "Insert" menu: the wide tool row folded into a
/// labeled chip — select, text, a "Shape" submenu of kinds, line, arrow,
/// "Table" and "Chart", which open the table and chart pickers in a sheet
/// (#1160), and
/// an "Image" submenu of sources, and a "New slide" submenu of layouts
/// (#1163) that adds a slide on the one picked after the selected slide. Choosing a drawing tool arms the canvas;
/// the next tap on the slide places the element.
///
/// Key prefixes: `slide_insert_menu` on the chip, `slide_insert_table` on
/// "Table", `slide_insert_chart` on "Chart", `slide_insert_shape` and
/// `slide_insert_image` and `slide_insert_slide` on the submenus; items keep the keys the wide row
/// gives them.
class SlidePhoneInsertMenu extends StatelessWidget {
  /// The menu for [actions].
  const SlidePhoneInsertMenu({
    required this.actions,
    required this.onOpenTable,
    required this.onOpenChart,
    super.key,
  });

  /// Opens the chart picker in a sheet.
  final VoidCallback onOpenChart;

  /// Opens the table picker in a sheet.
  final VoidCallback onOpenTable;

  /// What the tools do.
  final SlideToolbarActions actions;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      SlideChoiceMenuItem(choice: actions.select),
      SlideChoiceMenuItem(choice: actions.text),
      SubmenuButton(
        key: const ValueKey('slide_insert_shape'),
        leadingIcon: const Icon(QuarkIcons.shapes),
        menuChildren: [
          for (final c in actions.shapes) SlideChoiceMenuItem(choice: c),
        ],
        child: const Text('Shape'),
      ),
      SlideChoiceMenuItem(choice: actions.line),
      SlideChoiceMenuItem(choice: actions.arrow),
      Semantics(
        selected: actions.tableToolActive,
        child: MenuItemButton(
          key: const ValueKey('slide_insert_table'),
          leadingIcon: const Icon(QuarkIcons.insert_table),
          trailingIcon: actions.tableToolActive
              ? const Icon(QuarkIcons.check)
              : null,
          onPressed: onOpenTable,
          child: const Text('Table'),
        ),
      ),
      Semantics(
        selected: actions.chartToolActive,
        child: MenuItemButton(
          key: const ValueKey('slide_insert_chart'),
          leadingIcon: const Icon(QuarkIcons.insert_chart),
          trailingIcon: actions.chartToolActive
              ? const Icon(QuarkIcons.check)
              : null,
          onPressed: onOpenChart,
          child: const Text('Chart'),
        ),
      ),
      SubmenuButton(
        key: const ValueKey('slide_insert_image'),
        leadingIcon: const Icon(QuarkIcons.add_image),
        menuChildren: [
          for (final c in actions.imageSources) SlideChoiceMenuItem(choice: c),
        ],
        child: const Text('Image'),
      ),
      SubmenuButton(
        key: const ValueKey('slide_insert_slide'),
        leadingIcon: const Icon(QuarkIcons.slide_layout),
        menuChildren: [
          for (final c in actions.newSlideLayouts)
            SlideChoiceMenuItem(choice: c),
        ],
        child: const Text('New slide'),
      ),
    ],
    builder: (context, menu, _) => QuarkBarChip(
      key: const ValueKey('slide_insert_menu'),
      icon: QuarkIcons.insert_menu,
      label: 'Insert',
      tooltip: 'Insert text, shapes, lines, tables, charts and pictures',
      keepLabel: true,
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
