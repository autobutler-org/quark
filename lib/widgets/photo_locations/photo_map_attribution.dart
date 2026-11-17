import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// "© OpenStreetMap contributors", which the license of OpenStreetMap's data
/// requires on every map drawn from it (#3557): the Locations view on a
/// phone and a desktop, and the viewer's preview alike. It is always on
/// screen, never folded away behind a button, and links to the copyright
/// page. Drawn on the card color with the foreground color, so it keeps its
/// contrast over any tile in either theme.
///
/// Keyed `photo_map_attribution`.
class PhotoMapAttribution extends StatelessWidget {
  /// Creates the attribution.
  const PhotoMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.cardForeground,
      decoration: TextDecoration.underline,
    );
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingXs),
        child: Semantics(
          link: true,
          child: Material(
            color: tokens.card.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: InkWell(
              key: const ValueKey('photo_map_attribution'),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: () => launchUrl(
                Uri.parse(PhotoMapConfig.attributionUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.spacingSm,
                  vertical: tokens.spacingXs / 2,
                ),
                child: Text(
                  PhotoMapConfig.attribution,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
