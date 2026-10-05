import 'package:flutter/widgets.dart' show IconData, VoidCallback;
import 'package:quark_icons/quark_icons.dart';

import '../../models/cell_format.dart';
import '../data_sheet_controller.dart';
import 'data_sheet_palette.dart';

/// One formatting control as data: what it is called, whether it is on, and
/// what it does. The toolbar row and the phone menu draw the same choices.
class FormatChoice {
  /// The control's `ValueKey`.
  final String key;

  /// Its label in a menu and its tooltip on a button.
  final String label;

  /// Its glyph, if it has one.
  final IconData? icon;

  /// A color swatch shown in place of [icon].
  final DataSheetSwatch? swatch;

  /// Whether the selected cell already has it.
  final bool checked;

  /// What choosing it does, or null while nothing is selected.
  final VoidCallback? onSelected;

  const FormatChoice({
    required this.key,
    required this.label,
    this.icon,
    this.swatch,
    this.checked = false,
    this.onSelected,
  });
}

/// What the formatting controls do to a [DataSheetController]'s selection.
///
/// The controls read the highlighted cell's format, so a toggle reflects that
/// cell, and apply each change to the whole selected range as one undo step.
/// Bold on a range whose first cell is bold turns bold off everywhere, as in
/// Google Sheets.
class DataSheetFormatActions {
  /// The sheet the controls act on.
  final DataSheetController controller;

  /// Text colors the text color menu offers.
  final List<DataSheetSwatch> textColors;

  /// Fill colors the fill menu offers.
  final List<DataSheetSwatch> fillColors;

  DataSheetFormatActions(
    this.controller, {
    this.textColors = DataSheetPalette.text,
    this.fillColors = DataSheetPalette.fill,
  });

  /// The highlighted cell's format: the one the toggles show.
  CellFormat get current {
    final sel = controller.selection;
    return controller.formatAt(sel.contextRow, sel.contextCol);
  }

  /// Applies [change] to the selection, or null when nothing is selected.
  VoidCallback? _apply(CellFormat Function(CellFormat) change) {
    final range = controller.selection.contextRange;
    return range == null ? null : () => controller.applyFormat(range, change);
  }

  /// Bold on or off.
  FormatChoice get bold {
    final on = current.bold;
    return FormatChoice(
      key: 'format_bold',
      label: 'Bold',
      icon: QuarkIcons.format_bold,
      checked: on,
      onSelected: _apply((f) => f.withBold(!on)),
    );
  }

  /// Italic on or off.
  FormatChoice get italic {
    final on = current.italic;
    return FormatChoice(
      key: 'format_italic',
      label: 'Italic',
      icon: QuarkIcons.format_italic,
      checked: on,
      onSelected: _apply((f) => f.withItalic(!on)),
    );
  }

  /// The text colors, led by the theme's own.
  List<FormatChoice> get textColorChoices => _colors(
        'format_text_color',
        'Default',
        textColors,
        current.textColor,
        (f, argb) => f.withTextColor(argb),
      );

  /// The fill colors, led by none.
  List<FormatChoice> get fillChoices => _colors(
        'format_fill',
        'None',
        fillColors,
        current.fillColor,
        (f, argb) => f.withFillColor(argb),
      );

  List<FormatChoice> _colors(
    String prefix,
    String noneLabel,
    List<DataSheetSwatch> swatches,
    int? selected,
    CellFormat Function(CellFormat, int?) set,
  ) =>
      [
        FormatChoice(
          key: '${prefix}_none',
          label: noneLabel,
          checked: selected == null,
          onSelected: _apply((f) => set(f, null)),
        ),
        for (final (i, swatch) in swatches.indexed)
          FormatChoice(
            key: '${prefix}_$i',
            label: swatch.name,
            swatch: swatch,
            checked: selected == swatch.color.toARGB32(),
            onSelected: _apply((f) => set(f, swatch.color.toARGB32())),
          ),
      ];

  /// Left, center and right alignment. Choosing the alignment a cell already
  /// has puts it back to the default.
  List<FormatChoice> get alignChoices {
    final aligned = current.align;
    return [
      for (final (align, label, icon) in [
        (CellAlign.left, 'Align left', QuarkIcons.format_align_left),
        (CellAlign.center, 'Align center', QuarkIcons.format_align_center),
        (CellAlign.right, 'Align right', QuarkIcons.format_align_right),
      ])
        FormatChoice(
          key: 'format_align_${align.name}',
          label: label,
          icon: icon,
          checked: aligned == align,
          onSelected: _apply(
            (f) => f.withAlign(aligned == align ? null : align),
          ),
        ),
    ];
  }

  /// The number formats, each labeled with an example.
  List<FormatChoice> get numberFormatChoices => [
        for (final format in CellNumberFormat.values)
          FormatChoice(
            key: 'format_number_${format.name}',
            label: switch (format) {
              CellNumberFormat.general => 'Automatic',
              CellNumberFormat.number => 'Number  1,234.56',
              CellNumberFormat.currency => r'Currency  $1,234.56',
              CellNumberFormat.percent => 'Percent  12.34%',
              CellNumberFormat.date => 'Date  2025-01-31',
            },
            checked: current.numberFormat == format,
            onSelected: _apply((f) => f.withNumberFormat(format)),
          ),
      ];

  /// One fewer decimal place, down to none.
  FormatChoice get decreaseDecimals => _decimals(
        -1,
        'format_decimals_decrease',
        'Decrease decimal places',
        QuarkIcons.decimal_decrease,
      );

  /// One more decimal place, up to [CellFormat.maxDecimals].
  FormatChoice get increaseDecimals => _decimals(
        1,
        'format_decimals_increase',
        'Increase decimal places',
        QuarkIcons.decimal_increase,
      );

  /// Sets every selected cell to the highlighted cell's decimals plus [by].
  /// Disabled unless that cell's number format has decimals, and at either
  /// end of the range.
  FormatChoice _decimals(int by, String key, String label, IconData icon) {
    final format = current;
    final next = format.effectiveDecimals + by;
    final hasDecimals = const {
      CellNumberFormat.number,
      CellNumberFormat.currency,
      CellNumberFormat.percent,
    }.contains(format.numberFormat);
    return FormatChoice(
      key: key,
      label: label,
      icon: icon,
      onSelected: hasDecimals && next >= 0 && next <= CellFormat.maxDecimals
          ? _apply((f) => f.withDecimals(next))
          : null,
    );
  }

  /// Every format removed, values kept.
  FormatChoice get clear => FormatChoice(
        key: 'format_clear',
        label: 'Clear formatting',
        icon: QuarkIcons.format_clear,
        onSelected: _apply((_) => CellFormat.plain),
      );
}
