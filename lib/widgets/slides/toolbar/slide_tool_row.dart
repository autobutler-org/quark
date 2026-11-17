import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/slides/chart/slide_chart_menu_button.dart';
import 'package:quark/widgets/slides/find/slide_find_button.dart';
import 'package:quark/widgets/slides/table/slide_table_menu_button.dart';
import 'package:quark/widgets/slides/theme/slide_picker_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide slide toolbar's first row: the drawing tools — select, text,
/// the shape menu, line and arrow — the table, chart and picture menus, and the Theme and
/// Layout pickers (#1163), with the keyboard shortcuts button and the slide list's and properties panel's
/// toggles at the far end. The active tool is lit.
///
/// Key prefixes: `slide_tool_shape` on the shape menu, `slide_tool_table`
/// on the table menu (#1160), `slide_tool_chart` on the chart menu,
/// `slide_tool_image`
/// on the picture menu, `slide_theme_button` and `slide_layout_button` on
/// the pickers' chips, `slide_transition_button` on the Transition chip, `slide_find_open` on the find button,
/// `slide_shortcuts_button` on the shortcuts button,
/// `slide_list_toggle` and `slide_properties_toggle` on the toggles; the tools' own keys (see
/// [SlideToolbarActions]).
class SlideToolRow extends StatelessWidget {
  /// The tools of [actions]; [slidesOpen] and [propertiesOpen] light the
  /// toggles, which call [onToggleSlides] and [onToggleProperties].
  const SlideToolRow({
    required this.actions,
    required this.slidesOpen,
    required this.onToggleSlides,
    required this.propertiesOpen,
    required this.onToggleProperties,
    required this.onShowShortcuts,
    required this.findOpen,
    required this.onToggleFind,
    this.readOnly = false,
    super.key,
  });

  /// Whether the presentation is view only: the editing tools give way to
  /// the find and shortcuts buttons and the pane toggles.
  final bool readOnly;

  /// What the tools do.
  final SlideToolbarActions actions;

  /// Whether the slide list is showing.
  final bool slidesOpen;

  /// Shows or hides the slide list; null leaves its toggle out, for when
  /// the slides are a strip across the top that never hides.
  final VoidCallback? onToggleSlides;

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
                SlidePickerMenuButton(
                  controller: actions.controller,
                  kind: SlidePickerKind.transition,
                ),
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
      for (final pane in [
        if (onToggleSlides case final onToggle?)
          (
            id: 'list',
            name: 'slides',
            icon: QuarkIcons.slide_list,
            open: slidesOpen,
            onToggle: onToggle,
          ),
        (
          id: 'properties',
          name: 'properties',
          icon: QuarkIcons.properties,
          open: propertiesOpen,
          onToggle: onToggleProperties,
        ),
      ])
        QuarkBarIconButton(
          key: ValueKey('slide_${pane.id}_toggle'),
          icon: pane.icon,
          tooltip: '${pane.open ? 'Hide' : 'Show'} ${pane.name}',
          selected: pane.open,
          onPressed: pane.onToggle,
        ),
    ],
  );
}
