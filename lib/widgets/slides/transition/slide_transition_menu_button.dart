import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/transition/slide_transition_control.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The "Transition" chip in the wide slide toolbar (#1164): it opens the
/// [SlideTransitionControl] in a menu under it, which stays open while
/// choices are made so each can be previewed; Escape or a click elsewhere
/// closes it. It listens to [controller], so the open menu follows each
/// choice and undo.
///
/// Key prefixes: `slide_transition_button` on the chip, and the control's.
class SlideTransitionMenuButton extends StatelessWidget {
  /// A chip opening the transition picker for [controller].
  const SlideTransitionMenuButton({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  /// How wide the menu lays the picker out.
  static const double menuWidth = 296;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      menuChildren: [
        SizedBox(
          width: menuWidth,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) =>
                  SlideTransitionControl(controller: controller),
            ),
          ),
        ),
      ],
      builder: (context, menu, _) => QuarkBarChip(
        key: const ValueKey('slide_transition_button'),
        icon: QuarkIcons.slide_transition,
        label: 'Transition',
        tooltip: 'Choose how the show moves on to this slide',
        keepLabel: true,
        onPressed: controller.selectedSlide == null
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
