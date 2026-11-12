import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../token_fields.dart';

/// One color token drawn as a filled tile over its name and hex value.
class Swatch extends StatelessWidget {
  /// Creates the swatch for the token called [name].
  const Swatch({required this.name, required this.color, super.key});

  /// The token's name.
  final String name;

  /// The token's current color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
          ),
          SizedBox(height: tokens.spacingXs),
          Text(
            name,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            toHex(color),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: tokens.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
