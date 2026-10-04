import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_menu_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_font_size_stepper.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_group.dart';
import 'package:quark_icons/quark_icons.dart';

/// One [SlideToolbarGroup]'s controls laid out in the wide formatting row:
/// for text, the font menu, the size stepper, the style toggles and the
/// color; for a paragraph, the alignments and lists; for a shape, fill,
/// outline color, width and dash, corner radius and opacity; for arrange,
/// the stacking-order menu, duplicate and delete.
///
/// Key prefixes: [SlideToolbarGroup.key] on the run, and the controls' own
/// keys (see [SlideToolbarActions]).
class SlideFormatGroupControls extends StatelessWidget {
  /// The controls of [group], acting through [actions].
  const SlideFormatGroupControls({
    required this.group,
    required this.actions,
    super.key,
  });

  /// Which group.
  final SlideToolbarGroup group;

  /// What the controls do.
  final SlideToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final children = switch (group) {
      SlideToolbarGroup.text => [
        SlideChoiceMenuButton(
          buttonKey: 'slide_format_font',
          icon: QuarkIcons.font_family,
          label: a.fontFamilyLabel,
          tooltip: 'Font',
          choices: a.fontFamilies,
        ),
        SlideFontSizeStepper(
          size: a.fontSizeLabel,
          smaller: a.fontSmaller,
          larger: a.fontLarger,
        ),
        for (final c in a.textToggles) SlideChoiceButton(choice: c),
        SlideColorMenuButton(choice: a.textColor),
      ],
      SlideToolbarGroup.paragraph => [
        for (final c in [...a.alignments, ...a.lists])
          SlideChoiceButton(choice: c),
      ],
      SlideToolbarGroup.shape => [
        SlideColorMenuButton(choice: a.fill),
        SlideColorMenuButton(choice: a.strokeColor),
        SlideChoiceMenuButton(
          buttonKey: 'slide_format_stroke_width',
          icon: QuarkIcons.stroke_width,
          tooltip: 'Outline width',
          choices: a.strokeWidths,
        ),
        SlideChoiceMenuButton(
          buttonKey: 'slide_format_dash',
          icon: QuarkIcons.stroke_dash,
          tooltip: 'Outline style',
          choices: a.dashes,
        ),
        SlideChoiceMenuButton(
          buttonKey: 'slide_format_corner',
          icon: QuarkIcons.corner_radius,
          tooltip: 'Corner radius',
          choices: a.cornerRadii,
        ),
        SlideChoiceMenuButton(
          buttonKey: 'slide_format_opacity',
          icon: QuarkIcons.opacity,
          tooltip: 'Opacity',
          choices: a.opacities,
        ),
      ],
      SlideToolbarGroup.arrange => [
        SlideChoiceMenuButton(
          buttonKey: 'slide_arrange',
          icon: QuarkIcons.arrange,
          tooltip: 'Arrange',
          choices: a.arrange,
        ),
        SlideChoiceButton(choice: a.duplicate),
        SlideChoiceButton(choice: a.delete),
      ],
    };
    return Row(
      key: ValueKey(group.key),
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
