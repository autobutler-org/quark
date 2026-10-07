import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_share_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_item.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_group.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The phone slide toolbar's "Format" menu: the wide formatting row folded
/// into a labeled chip, one submenu per [SlideToolbarGroup] that applies to
/// the selection, holding every control the row has, then "Theme" and
/// "Slide layout" (#1163), which open their pickers in a bottom sheet,
/// "Transition" (#1164), which opens the slide's transition picker in a
/// sheet, "Find and replace" (#1176), which opens the find bar,
/// "Properties",
/// which opens the properties sheet, "Share" (#1170), which opens the share
/// sheet (key `slide_format_share`), "Zoom", which the phone's bar has
/// no room for otherwise, and "Keyboard shortcuts".
///
/// Key prefixes: `slide_format_menu` on the chip, [SlideToolbarGroup.key]
/// on each group's submenu, `<key>_menu` on the font, color, width, style,
/// corner and opacity submenus; items keep the keys the wide row gives
/// them; `slide_format_theme` on "Theme", `slide_format_layout` on "Slide
/// layout", `slide_format_transition` on "Transition", `slide_format_find` on "Find and replace", `slide_format_properties` on "Properties", `slide_zoom_menu` on
/// "Zoom" and `slide_menu_zoom_out`, `slide_menu_zoom_fit` and
/// `slide_menu_zoom_in` on its items, `slide_format_shortcuts` on
/// "Keyboard shortcuts".
class SlidePhoneFormatMenu extends StatelessWidget {
  /// The menu for [actions].
  const SlidePhoneFormatMenu({
    required this.actions,
    required this.onOpenProperties,
    required this.onShowShortcuts,
    required this.onOpenTheme,
    required this.onOpenLayout,
    required this.onOpenTransition,
    required this.onFind,
    this.onShare,
    this.readOnly = false,
    super.key,
  });

  /// Opens the theme picker in a sheet.
  final VoidCallback onOpenTheme;

  /// Opens the selected slide's layout picker in a sheet.
  final VoidCallback onOpenLayout;

  /// Opens the selected slide's transition picker in a sheet.
  final VoidCallback onOpenTransition;

  /// Opens the find bar.
  final VoidCallback onFind;

  /// Opens the share sheet; null leaves "Share" out.
  final VoidCallback? onShare;

  /// Whether the presentation is view only: the formatting groups, "Theme"
  /// and "Slide layout" are left out.
  final bool readOnly;

  /// What the controls do.
  final SlideToolbarActions actions;

  /// Opens the properties sheet: position, size and alt text.
  final VoidCallback onOpenProperties;

  /// Opens the keyboard shortcuts dialog.
  final VoidCallback onShowShortcuts;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    SubmenuButton choices(
      String key,
      String label,
      IconData icon,
      List<SlideToolbarChoice> choices,
    ) => SubmenuButton(
      key: ValueKey('${key}_menu'),
      leadingIcon: Icon(icon),
      menuChildren: [for (final c in choices) SlideChoiceMenuItem(choice: c)],
      child: Text(label),
    );
    SubmenuButton color(SlideColorChoice choice) => SubmenuButton(
      key: ValueKey('${choice.key}_menu'),
      leadingIcon: Icon(choice.icon),
      menuChildren: [SlideColorPalette(choice: choice)],
      child: Text(choice.label),
    );
    List<Widget> controls(SlideToolbarGroup group) => switch (group) {
      SlideToolbarGroup.clipboard => [
        for (final c in [a.copy, a.cut, a.paste, a.duplicate])
          SlideChoiceMenuItem(choice: c),
      ],
      SlideToolbarGroup.text => [
        choices(
          'slide_format_font',
          'Font: ${a.fontFamilyLabel}',
          QuarkIcons.font_family,
          a.fontFamilies,
        ),
        SlideChoiceMenuItem(choice: a.fontLarger),
        SlideChoiceMenuItem(choice: a.fontSmaller),
        for (final c in a.textToggles) SlideChoiceMenuItem(choice: c),
        color(a.textColor),
      ],
      SlideToolbarGroup.paragraph => [
        for (final c in [...a.alignments, ...a.lists])
          SlideChoiceMenuItem(choice: c),
      ],
      SlideToolbarGroup.shape => [
        color(a.fill),
        color(a.strokeColor),
        choices(
          'slide_format_stroke_width',
          'Outline width',
          QuarkIcons.stroke_width,
          a.strokeWidths,
        ),
        choices(
          'slide_format_dash',
          'Outline style',
          QuarkIcons.stroke_dash,
          a.dashes,
        ),
        choices(
          'slide_format_corner',
          'Corner radius',
          QuarkIcons.corner_radius,
          a.cornerRadii,
        ),
        choices(
          'slide_format_opacity',
          'Opacity',
          QuarkIcons.opacity,
          a.opacities,
        ),
      ],
      SlideToolbarGroup.arrange => [
        for (final c in a.arrange) SlideChoiceMenuItem(choice: c),
        choices(
          'slide_align',
          'Align',
          QuarkIcons.align_elements_left,
          a.elementAlignments,
        ),
        if (a.canDistribute)
          choices(
            'slide_distribute',
            'Distribute',
            QuarkIcons.distribute_horizontal,
            a.distributions,
          ),
        if (a.canMatchSize)
          choices(
            'slide_match_size',
            'Match size',
            QuarkIcons.match_size,
            a.sizeMatches,
          ),
        if (a.canGroup) SlideChoiceMenuItem(choice: a.group),
        if (a.canUngroup) SlideChoiceMenuItem(choice: a.ungroup),
        SlideChoiceMenuItem(choice: a.delete),
      ],
    };
    final groups = [
      for (final group in SlideToolbarGroup.values)
        if (!readOnly && group.appliesTo(a)) group,
    ];
    return MenuAnchor(
      menuChildren: [
        for (final group in groups)
          SubmenuButton(
            key: ValueKey(group.key),
            leadingIcon: Icon(group.icon),
            menuChildren: controls(group),
            child: Text(group.label),
          ),
        MenuItemButton(
          key: const ValueKey('slide_format_find'),
          leadingIcon: const Icon(QuarkIcons.search_rounded),
          onPressed: onFind,
          child: const Text('Find and replace'),
        ),
        if (!readOnly) ...[
          MenuItemButton(
            key: const ValueKey('slide_format_theme'),
            leadingIcon: const Icon(QuarkIcons.slide_theme),
            onPressed: onOpenTheme,
            child: const Text('Theme'),
          ),
          MenuItemButton(
            key: const ValueKey('slide_format_layout'),
            leadingIcon: const Icon(QuarkIcons.slide_layout),
            onPressed: onOpenLayout,
            child: const Text('Slide layout'),
          ),
          MenuItemButton(
            key: const ValueKey('slide_format_transition'),
            leadingIcon: const Icon(QuarkIcons.slide_transition),
            onPressed: onOpenTransition,
            child: const Text('Transition'),
          ),
        ],
        MenuItemButton(
          key: const ValueKey('slide_format_properties'),
          leadingIcon: const Icon(QuarkIcons.properties),
          onPressed: onOpenProperties,
          child: const Text('Properties'),
        ),
        SubmenuButton(
          key: const ValueKey('slide_zoom_menu'),
          leadingIcon: const Icon(QuarkIcons.zoom_in),
          menuChildren: [
            for (final c in a.zoom) SlideChoiceMenuItem(choice: c),
          ],
          child: const Text('Zoom'),
        ),
        if (onShare != null)
          MenuItemButton(
            key: const ValueKey('slide_format_share'),
            leadingIcon: const Icon(QuarkIcons.share_outlined),
            onPressed: onShare,
            child: const Text(SlideShareButton.label),
          ),
        MenuItemButton(
          key: const ValueKey('slide_format_shortcuts'),
          leadingIcon: const Icon(QuarkIcons.keyboard_shortcuts),
          onPressed: onShowShortcuts,
          child: const Text('Keyboard shortcuts'),
        ),
      ],
      builder: (context, menu, _) => QuarkBarChip(
        key: const ValueKey('slide_format_menu'),
        icon: QuarkIcons.format_menu,
        label: 'Format',
        tooltip: 'Format the selection, its properties and the zoom',
        keepLabel: true,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
