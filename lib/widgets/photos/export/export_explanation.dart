import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What a photo export does, in plain words (#3501): it makes real copies
/// that open anywhere, a photo in several albums is copied into each album's
/// folder, and it is not a backup of the Quark, since nothing in Quark
/// changes and only the copies leave.
///
/// Key prefix: `export_explanation`.
class ExportExplanation extends StatelessWidget {
  /// Creates the explanation.
  const ExportExplanation({super.key});

  /// The three things the export says before it starts, in order.
  static const List<String> points = [
    'Quark makes real copies of your photos, not links, so they open on any '
        'computer or phone.',
    "A photo that is in more than one album is copied into each album's "
        'folder.',
    'This is not a backup of your Quark. Your photos and albums stay just as '
        'they are. Only the copies leave.',
  ];

  /// What the list beside the copies is for.
  static const String manifest =
      'A list called manifest.csv goes with them. It says where each photo '
      'came from, when it was taken, and which albums it is in.';

  static const _icons = [
    QuarkIcons.content_copy,
    QuarkIcons.photo_album_outlined,
    QuarkIcons.info_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      key: const ValueKey('export_explanation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icons[i], size: 18, color: tokens.mutedForeground),
                const SizedBox(width: 8),
                Expanded(child: Text(points[i], style: style)),
              ],
            ),
          ),
        Text(manifest, style: style?.copyWith(color: tokens.mutedForeground)),
      ],
    );
  }
}
