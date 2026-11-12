import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../token_fields.dart';
import 'radius_sample.dart';
import 'swatch.dart';

/// Every token in the current theme, drawn from the theme itself.
///
/// This is the gallery's own canary: edit a color in the theme panel and the
/// matching swatch has to move with it.
class TokenSwatches extends StatelessWidget {
  /// Creates the swatch sheet.
  const TokenSwatches({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Colors', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: tokens.spacingSm),
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingSm,
          children: [
            for (final field in colorFields)
              Swatch(name: field.name, color: field.read(tokens)),
          ],
        ),
        SizedBox(height: tokens.spacingLg),
        Text('Radii', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: tokens.spacingSm),
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingSm,
          children: [
            RadiusSample(name: 'radiusSm', radius: tokens.radiusSm),
            RadiusSample(name: 'radiusMd', radius: tokens.radiusMd),
            RadiusSample(name: 'radiusLg', radius: tokens.radiusLg),
          ],
        ),
        SizedBox(height: tokens.spacingLg),
        Text('Spacing', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: tokens.spacingSm),
        for (final step in [
          ('spacingXs', tokens.spacingXs),
          ('spacingSm', tokens.spacingSm),
          ('spacingMd', tokens.spacingMd),
          ('spacingLg', tokens.spacingLg),
          ('spacingXl', tokens.spacingXl),
        ])
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacingXs),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    step.$1,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(width: step.$2, height: 12, color: tokens.primary),
                SizedBox(width: tokens.spacingSm),
                Text(
                  step.$2.toStringAsFixed(0),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: tokens.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
