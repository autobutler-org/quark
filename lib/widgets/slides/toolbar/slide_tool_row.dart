import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_menu_button.dart';
import 'package:quark/widgets/slides/find/slide_find_button.dart';
import 'package:quark/widgets/slides/table/slide_table_menu_button.dart';
import 'package:quark/widgets/slides/theme/slide_picker_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark/widgets/slides/transition/slide_transition_menu_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide slide toolbar's first row: the drawing tools — select, text,
/// the shape menu, line and arrow — the table, chart and picture menus, and the Theme and
/// Layout pickers (#1163), with the keyboard shortcuts button and the properties panel's toggle at the far
/// end. The active tool is lit.
///
/// Key prefixes: `slide_tool_shape` on the shape menu, `slide_tool_table`
/// on the table menu (#1160), `slide_tool_chart` on the chart menu,
/// `slide_tool_image`
/// on the picture menu, `slide_theme_button` and `slide_layout_button` on
/// the pickers' chips, `slide_transition_button` on the Transition chip, `slide_find_open` on the find button,
/// `slide_shortcuts_button` on the shortcuts button,
/// `slide_properties_toggle` on the toggle; the tools' own keys (see
/// [SlideToolbarActions]).
class SlideToolRow extends StatelessWidget {
  /// The tools of [actions]; [propertiesOpen] lights the toggle, which
  /// calls [onToggleProperties].
  const SlideToolRow({
    required this.actions,
    required this.propertiesOpen,
    required this.onToggleProperties,
    required this.onShowShortcuts,
    required this.findOpen,
    required this.onToggleFind,
    this.readOnly = false,
    super.key,
  });

  /// Whether the presentation is view only: the editing tools give way to
  /// the find, shortcuts and properties buttons.
  final bool readOnly;

  /// What the tools do.
  final SlideToolbarActions actions;

  /// Whether the properties panel is showing.
  final bool propertiesOpen;

  /// Shows or hides the properties panel.
  final VoidCallback onToggleProperties;

  /// Opens the keyboard shortcuts dialog.
  final VoidCallback onShowShortcuts;

  /// Whether the find bar is showing.
  final bool findOpen;

  /// Opens the find bar, or closes it when it is open.
  final VoidCallback onToggleFind;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (readOnly)
        const Spacer()
      else
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
                SlideTableMenuButton(actions: actions),
                SlideChartMenuButton(actions: actions),
                SlideChoiceMenuButton(
                  buttonKey: 'slide_tool_image',
                  icon: QuarkIcons.add_image,
                  tooltip: 'Insert image',
                  choices: actions.imageSources,
                ),
                SlidePickerMenuButton(
                  controller: actions.controller,
                  kind: SlidePickerKind.theme,
                ),
                SlidePickerMenuButton(
                  controller: actions.controller,
                  kind: SlidePickerKind.layout,
                ),
                SlideTransitionMenuButton(controller: actions.controller),
              ],
            ),
          ),
        ),
      SlideFindButton(isOpen: findOpen, onPressed: onToggleFind),
      QuarkBarIconButton(
        key: const ValueKey('slide_shortcuts_button'),
        icon: QuarkIcons.keyboard_shortcuts,
        tooltip: 'Keyboard shortcuts',
        onPressed: onShowShortcuts,
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
