import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide panel's split "New slide" action (#1163): a tap on the add
/// button adds a slide ([onAdd]) — on the current slide's layout, or title
/// and content after a title or blank slide (#2899); a long
/// press on it, or the chevron beside it, opens a menu of [layouts] to
/// build the new slide on ([onAddWithLayout]).
///
/// The two buttons sit side by side down a wide window's panel and one
/// over the other across a phone's strip, by [direction].
///
/// Key prefixes: `slide_panel_add` on the add button, `slide_panel_add_menu`
/// on the chevron and `slide_panel_add_<layout id>` on the menu's rows.
class SlideNewSlideButton extends StatelessWidget {
  /// The split button over [layouts].
  const SlideNewSlideButton({
    required this.layouts,
    required this.onAdd,
    required this.onAddWithLayout,
    this.direction = Axis.horizontal,
    super.key,
  });

  /// The layouts the menu offers, in order.
  final List<SlideLayout> layouts;

  /// Adds a slide on the default layout for the current slide.
  final VoidCallback onAdd;

  /// Adds a slide on the layout with the id given.
  final ValueChanged<String> onAddWithLayout;

  /// Which way the two buttons run.
  final Axis direction;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final layout in layouts)
        MenuItemButton(
          key: ValueKey('slide_panel_add_${layout.id}'),
          leadingIcon: const Icon(QuarkIcons.slide_layout),
          onPressed: () => onAddWithLayout(layout.id),
          child: Text(layout.name),
        ),
    ],
    builder: (context, menu, _) {
      void toggle() => menu.isOpen ? menu.close() : menu.open();
      return Flex(
        direction: direction,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            // The chevron is a screen reader's way to the same menu.
            excludeFromSemantics: true,
            onLongPress: toggle,
            // A long press opens the menu rather than the tooltip, which a
            // mouse still shows on hover.
            child: TooltipTheme(
              data: TooltipTheme.of(
                context,
              ).copyWith(triggerMode: TooltipTriggerMode.manual),
              child: QuarkBarIconButton(
                key: const ValueKey('slide_panel_add'),
                icon: QuarkIcons.add_rounded,
                tooltip: 'New slide',
                onPressed: onAdd,
              ),
            ),
          ),
          QuarkBarIconButton(
            key: const ValueKey('slide_panel_add_menu'),
            icon: QuarkIcons.expand_more,
            tooltip: 'New slide with layout',
            onPressed: toggle,
          ),
        ],
      );
    },
  );
}
