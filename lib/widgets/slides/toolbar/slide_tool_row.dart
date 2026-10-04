import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide slide toolbar's first row: the drawing tools — select, text,
/// the shape menu, line and arrow — and the picture menu, with the
/// properties panel's toggle at the far end. The active tool is lit.
///
/// Key prefixes: `slide_tool_shape` on the shape menu, `slide_tool_image`
/// on the picture menu, `slide_properties_toggle` on the toggle; the tools'
/// own keys (see [SlideToolbarActions]).
class SlideToolRow extends StatelessWidget {
  /// The tools of [actions]; [propertiesOpen] lights the toggle, which
  /// calls [onToggleProperties].
  const SlideToolRow({
    required this.actions,
    required this.propertiesOpen,
    required this.onToggleProperties,
    super.key,
  });

  /// What the tools do.
  final SlideToolbarActions actions;

  /// Whether the properties panel is showing.
  final bool propertiesOpen;

  /// Shows or hides the properties panel.
  final VoidCallback onToggleProperties;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SlideChoiceButton(choice: actions.select),
              SlideChoiceButton(choice: actions.text),
              SlideChoiceMenuButton(
                buttonKey: 'slide_tool_shape',
                icon: QuarkIcons.shapes,
                tooltip: 'Insert shape',
                selected: actions.shapeToolActive,
                choices: actions.shapes,
              ),
              SlideChoiceButton(choice: actions.line),
              SlideChoiceButton(choice: actions.arrow),
              SlideChoiceMenuButton(
                buttonKey: 'slide_tool_image',
                icon: QuarkIcons.add_image,
                tooltip: 'Insert image',
                choices: actions.imageSources,
              ),
            ],
          ),
        ),
      ),
      QuarkBarIconButton(
        key: const ValueKey('slide_properties_toggle'),
        icon: QuarkIcons.properties,
        tooltip: propertiesOpen ? 'Hide properties' : 'Show properties',
        selected: propertiesOpen,
        onPressed: onToggleProperties,
      ),
    ],
  );
}
