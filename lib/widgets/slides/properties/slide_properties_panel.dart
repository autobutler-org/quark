import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/chart/slide_chart_properties_section.dart';
import 'package:quark/widgets/slides/properties/slide_alt_text_field.dart';
import 'package:quark/widgets/slides/properties/slide_number_field.dart';
import 'package:quark/widgets/slides/table/slide_table_properties_section.dart';
import 'package:quark/widgets/slides/theme/slide_layout_control.dart';
import 'package:quark/widgets/slides/theme/slide_theme_control.dart';
import 'package:quark/widgets/slides/toolbar/slide_color_palette.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark/widgets/slides/transition/slide_transition_control.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's properties (#1167): the one selected element's
/// position, size and rotation as numbers, a selected picture's alt text,
/// a selected table's size and style (#1160, [SlideTablePropertiesSection]),
/// a selected chart's kind, size of data and title
/// ([SlideChartPropertiesSection]),
/// and the slide's background color (#1174) from the toolbar's swatches or
/// a hex code — "Theme background" clears it so the slide follows the
/// theme — then the slide's layout, its transition (#1164) and the presentation's
/// theme (#1163): [SlideLayoutControl], [SlideTransitionControl] and
/// [SlideThemeControl].
///
/// A wide screen shows it down the right of the canvas, collapsible from
/// the toolbar; a phone opens it as a bottom sheet from the toolbar's
/// "Format" menu. Either way it reads [controller] and each field is one
/// undo step through it, saved when the field is submitted or left.
///
/// A view-only presentation ([SlideEditorController.isReadOnly]) shows the
/// position, size and alt text in fields that take no input, and leaves out
/// the background, layout and theme sections and shows the transition
/// with its choices off.
///
/// Position and size are in slide units (a 16:9 slide is 1920 by 1080),
/// rotation in degrees clockwise.
///
/// Key prefixes: `slide_properties` on the panel; `slide_prop_x`,
/// `slide_prop_y`, `slide_prop_width`, `slide_prop_height`,
/// `slide_prop_rotation` and `slide_prop_alt_text` on the fields;
/// `slide_prop_hint` on the note shown without exactly one element
/// selected; `slide_background` on the background palette, with its
/// swatches `slide_background_<index>`, `slide_background_none` and
/// `slide_background_hex`; the layout and theme pickers' own.
class SlidePropertiesPanel extends StatelessWidget {
  /// The properties of [controller]'s selection.
  const SlidePropertiesPanel({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  /// The panel's width beside the canvas.
  static const double sideWidth = 280;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final element = controller.singleSelected;
    final readOnly = controller.isReadOnly;
    final count = controller.selectedElementIds.length;
    final frame = element?.frame;
    // A view-only deck shows the values in fields that do not take input.
    final rows = frame == null
        ? const <List<(String, String, double, String, ValueChanged<double>)>>[]
        : [
            [
              ('x', 'X', frame.x, '', (v) => controller.setFrame(x: v)),
              ('y', 'Y', frame.y, '', (v) => controller.setFrame(y: v)),
            ],
            [
              (
                'width',
                'Width',
                frame.width,
                '',
                (v) => controller.setFrame(width: v),
              ),
              (
                'height',
                'Height',
                frame.height,
                '',
                (v) => controller.setFrame(height: v),
              ),
            ],
            [
              (
                'rotation',
                'Rotation',
                frame.rotation,
                '°',
                (v) => controller.setFrame(rotation: v),
              ),
            ],
          ];

    return Padding(
      key: const ValueKey('slide_properties'),
      padding: EdgeInsets.all(tokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingLg,
        children: [
          QuarkSection(
            title: 'Position and size',
            child: element == null
                ? Text(
                    count == 0
                        ? 'Select an element to set its position and size.'
                        : '$count elements selected. Select one to set its '
                              'position and size.',
                    key: const ValueKey('slide_prop_hint'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.mutedForeground,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: tokens.spacingSm,
                    children: [
                      for (final row in rows)
                        Row(
                          spacing: tokens.spacingSm,
                          children: [
                            for (final (name, label, value, unit, set) in row)
                              Expanded(
                                child: SlideNumberField(
                                  key: ValueKey('slide_prop_$name'),
                                  label: label,
                                  value: value,
                                  unit: unit,
                                  onSubmitted: readOnly ? null : set,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
          if (element is ImageElement)
            QuarkSection(
              title: 'Accessibility',
              child: SlideAltTextField(
                value: element.altText,
                onSubmitted: controller.setAltText,
                readOnly: readOnly,
              ),
            ),
          if (element is TableElement)
            SlideTablePropertiesSection(
              rows: element.rowCount,
              columns: element.columnCount,
              headerRow: element.headerRow,
              bandedRows: element.bandedRows,
              onHeaderRowChanged: readOnly
                  ? null
                  : (on) => controller.setTableStyle(headerRow: on),
              onBandedRowsChanged: readOnly
                  ? null
                  : (on) => controller.setTableStyle(bandedRows: on),
            ),
          if (element is ChartElement)
            SlideChartPropertiesSection(
              chart: element,
              onTitleChanged: readOnly
                  ? null
                  : (title) => controller.setChartOptions(title: title),
            ),
          if (!readOnly && controller.selectedSlide != null)
            QuarkSection(
              title: 'Slide background',
              child: SlideColorPalette(
                key: const ValueKey('slide_background'),
                width: double.infinity,
                choice: SlideColorChoice(
                  key: 'slide_background',
                  label: 'Background color',
                  icon: QuarkIcons.slide_background,
                  current: controller.slideBackgroundColor,
                  noneLabel: 'Theme background',
                  theme: controller.theme,
                  onChanged: controller.setSlideBackgroundColor,
                ),
              ),
            ),
          if (!readOnly && controller.selectedSlide != null)
            QuarkSection(
              title: 'Slide layout',
              child: SlideLayoutControl(controller: controller),
            ),
          if (controller.selectedSlide != null)
            QuarkSection(
              title: 'Transition',
              child: SlideTransitionControl(controller: controller),
            ),
          if (!readOnly)
            QuarkSection(
              title: 'Theme',
              child: SlideThemeControl(controller: controller),
            ),
        ],
      ),
    );
  }
}
