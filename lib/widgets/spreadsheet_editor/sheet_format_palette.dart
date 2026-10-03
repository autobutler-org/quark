import 'package:data_table/data_sheet.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:quark_widgets/quark_widgets.dart';

/// The text colors the sheets formatting toolbar offers, drawn from [tokens]
/// so a sheet's colors match the rest of Quark.
///
/// Colors repeated between tokens (the event palette starts with `primary`)
/// are listed once.
List<DataSheetSwatch> sheetTextSwatches(QuarkTokens tokens) {
  final seen = <Color>{};
  return [
    for (final swatch in [
      DataSheetSwatch('Gray', tokens.mutedForeground),
      DataSheetSwatch('Red', tokens.error),
      DataSheetSwatch('Amber', tokens.warning),
      DataSheetSwatch('Green', tokens.success),
      DataSheetSwatch('Blue', tokens.primary),
      for (final (i, color) in tokens.eventColors.indexed)
        DataSheetSwatch('Accent ${i + 1}', color),
    ])
      if (seen.add(swatch.color)) swatch,
  ];
}

/// The fill colors: [sheetTextSwatches] at [fillAlpha], so the theme's text
/// stays readable over them in light and dark.
List<DataSheetSwatch> sheetFillSwatches(QuarkTokens tokens) => [
  for (final swatch in sheetTextSwatches(tokens))
    DataSheetSwatch(swatch.name, swatch.color.withValues(alpha: fillAlpha)),
];

/// How opaque a fill swatch is.
const double fillAlpha = 0.25;
