import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One radius token drawn as an outlined tile with that corner radius.
class RadiusSample extends StatelessWidget {
  /// Creates the sample for the token called [name].
  const RadiusSample({required this.name, required this.radius, super.key});

  /// The token's name.
  final String name;

  /// The token's current radius.
  final double radius;

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
              color: tokens.card,
              border: Border.all(color: tokens.primary, width: 2),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          SizedBox(height: tokens.spacingXs),
          Text(
            '$name ${radius.toStringAsFixed(0)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
