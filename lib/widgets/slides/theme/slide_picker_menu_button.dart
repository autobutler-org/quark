import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/theme/slide_layout_control.dart';
import 'package:quark/widgets/slides/theme/slide_theme_control.dart';
import 'package:quark/widgets/slides/transition/slide_transition_control.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Which picker a [SlidePickerMenuButton] opens.
enum SlidePickerKind {
  /// The presentation's theme: [SlideThemeControl].
  theme,

  /// The selected slide's layout: [SlideLayoutControl].
  layout,

  /// The selected slide's transition: [SlideTransitionControl] (#1164).
  transition,
}

/// A labeled chip in the wide slide toolbar (#1163) that opens the theme,
/// layout or transition picker, by [kind], in a menu under it. The menu
/// stays open while picks are made, so each can be seen on the canvas or
/// previewed; Escape or a click elsewhere closes it. The transition chip is
/// off with no slide selected, the others with no presentation.
///
/// It listens to [controller], so the open picker follows each pick and
/// undo.
///
/// Key prefixes: `slide_theme_button`, `slide_layout_button` or
/// `slide_transition_button` on the chip, and the picker's.
class SlidePickerMenuButton extends StatelessWidget {
  /// A chip opening [kind]'s picker for [controller].
  const SlidePickerMenuButton({
    required this.controller,
    required this.kind,
    super.key,
  });

  /// The open presentation.
  final SlideEditorController controller;

  /// Which picker the menu holds.
  final SlidePickerKind kind;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // The theme and layout menus are two cards a row wide.
    final (key, icon, label, tooltip, width, enabled) = switch (kind) {
      SlidePickerKind.theme => (
        'slide_theme_button',
        QuarkIcons.slide_theme,
        'Theme',
        'Choose the presentation\'s theme',
        272.0,
        controller.presentation != null,
      ),
      SlidePickerKind.layout => (
        'slide_layout_button',
        QuarkIcons.slide_layout,
        'Layout',
        'Choose this slide\'s layout',
        272.0,
        controller.presentation != null,
      ),
      SlidePickerKind.transition => (
        'slide_transition_button',
        QuarkIcons.slide_transition,
        'Transition',
        'Choose how the show moves on to this slide',
        296.0,
        controller.selectedSlide != null,
      ),
    };
    return MenuAnchor(
      menuChildren: [
        SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => switch (kind) {
                SlidePickerKind.theme => SlideThemeControl(
                  controller: controller,
                ),
                SlidePickerKind.layout => SlideLayoutControl(
                  controller: controller,
                ),
                SlidePickerKind.transition => SlideTransitionControl(
                  controller: controller,
                ),
              },
            ),
          ),
        ),
      ],
      builder: (context, menu, _) => QuarkBarChip(
        key: ValueKey(key),
        icon: icon,
        label: label,
        tooltip: tooltip,
        keepLabel: true,
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
    );
  }
}
