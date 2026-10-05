import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/theme/slide_layout_control.dart';
import 'package:quark/widgets/slides/theme/slide_theme_control.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Which picker a [SlidePickerMenuButton] opens.
enum SlidePickerKind {
  /// The presentation's theme: [SlideThemeControl].
  theme,

  /// The selected slide's layout: [SlideLayoutControl].
  layout,
}

/// A labeled chip in the wide slide toolbar (#1163) that opens the theme or
/// the layout picker, by [kind], in a menu under it. The menu stays open
/// while picks are made, so each can be seen on the canvas; Escape or a
/// click elsewhere closes it.
///
/// It listens to [controller], so the open picker follows each pick and
/// undo.
///
/// Key prefixes: `slide_theme_button` or `slide_layout_button` on the
/// chip, and the picker's.
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

  /// How wide the menu lays the picker out: two cards a row.
  static const double menuWidth = 272;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (key, icon, label, tooltip) = switch (kind) {
      SlidePickerKind.theme => (
        'slide_theme_button',
        QuarkIcons.slide_theme,
        'Theme',
        'Choose the presentation\'s theme',
      ),
      SlidePickerKind.layout => (
        'slide_layout_button',
        QuarkIcons.slide_layout,
        'Layout',
        'Choose this slide\'s layout',
      ),
    };
    return MenuAnchor(
      menuChildren: [
        SizedBox(
          width: menuWidth,
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
        onPressed: controller.presentation == null
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
