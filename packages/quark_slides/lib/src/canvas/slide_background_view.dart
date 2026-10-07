import 'package:flutter/widgets.dart';

import '../model/slide_background.dart';
import '../theme/slide_theme.dart';
import '../theme/theme_color.dart';
import 'slide_image_source.dart';

/// Fills a slide with its [background]: the color, with the image drawn
/// over it to cover the slide when there is one and an [imageBuilder] to
/// draw it. A `null` background, or one with no color, shows [theme]'s
/// [ThemeColor.background].
class SlideBackgroundView extends StatelessWidget {
  /// Creates a background.
  const SlideBackgroundView({
    super.key,
    required this.background,
    required this.theme,
    this.imageBuilder,
  });

  /// The slide's background, or `null` for the default.
  final SlideBackground? background;

  /// Supplies the default slide color and resolves a role color.
  final SlideTheme theme;

  /// Draws the background image.
  final SlideImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final color = background?.color;
    final image = background?.image;
    return ColoredBox(
      color: Color(
        color == null
            ? theme.colors[ThemeColor.background]
            : color.resolve(theme),
      ),
      child: image == null || imageBuilder == null
          ? const SizedBox.expand()
          : SizedBox.expand(
              child: imageBuilder!(
                context,
                SlideImageSource(image, fit: BoxFit.cover),
              ),
            ),
    );
  }
}
