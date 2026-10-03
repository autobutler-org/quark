import 'package:flutter/material.dart' hide Icons;

import '../data_sheet_controller.dart';
import 'data_sheet_palette.dart';
import 'format_actions.dart';
import 'format_phone_menu.dart';
import 'format_toolbar_row.dart';

/// The formatting toolbar for a [DataSheetController]: bold, italic, text
/// color, fill, alignment, number format (automatic, number, currency,
/// percent, date) and its decimal places, and clear formatting.
///
/// Every change applies to the whole selected range as one undo step; the
/// toggles show the highlighted cell's format. Narrower than
/// [compactBreakpoint], the controls fold into one labeled "Format" menu
/// rather than an anonymous overflow.
///
/// The app supplies the colors: [textColors] and [fillColors] default to
/// [DataSheetPalette], and Quark passes swatches derived from its design
/// tokens.
///
/// Keys: `format_bold`, `format_italic`, `format_text_color`, `format_fill`,
/// `format_align_left`, `format_align_center`, `format_align_right`,
/// `format_number`, `format_decimals_decrease`, `format_decimals_increase`,
/// `format_clear`; on a narrow screen the menu button is `format_menu` and
/// the alignment submenu `format_align`. Menu items are
/// `format_text_color_none`, `format_text_color_<i>`, `format_fill_none`,
/// `format_fill_<i>` (by palette index), and `format_number_<format>`
/// (`general`, `number`, `currency`, `percent`, `date`).
///
/// ```dart
/// Column(children: [
///   DataSheetFormatBar(controller: controller),
///   Expanded(child: DataSheet(controller: controller, table: table)),
/// ])
/// ```
class DataSheetFormatBar extends StatelessWidget {
  /// The sheet the toolbar formats.
  final DataSheetController controller;

  /// The text colors offered.
  final List<DataSheetSwatch> textColors;

  /// The fill colors offered.
  final List<DataSheetSwatch> fillColors;

  /// Below this width the toolbar folds into the "Format" menu.
  final double compactBreakpoint;

  const DataSheetFormatBar({
    super.key,
    required this.controller,
    this.textColors = DataSheetPalette.text,
    this.fillColors = DataSheetPalette.fill,
    this.compactBreakpoint = 600,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final actions = DataSheetFormatActions(
          controller,
          textColors: textColors,
          fillColors: fillColors,
        );
        return LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < compactBreakpoint
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FormatPhoneMenu(actions: actions),
                    )
                  : FormatToolbarRow(actions: actions),
        );
      },
    );
  }
}
