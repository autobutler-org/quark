import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../quark_markdown_view.dart';

/// An image inside a `QuarkMarkdownView`'s text. It loads nothing: it shows
/// what [imageBuilder] returns for [src] and [alt], or, without a builder, a
/// bordered placeholder carrying the alt text.
///
/// Key prefixes: none of its own. The view keys each image
/// `markdown_image_<n>`.
///
/// ```dart
/// MarkdownImage(src: 'cat.png', alt: 'A cat', style: bodyStyle);
/// ```
class MarkdownImage extends StatelessWidget {
  /// Creates the image for [src].
  const MarkdownImage({
    required this.src,
    required this.alt,
    required this.style,
    this.imageBuilder,
    super.key,
  });

  /// The image's source, exactly as the document wrote it.
  final String src;

  /// The image's alt text; empty when the document gave none.
  final String alt;

  /// The text style around the image, used for the placeholder's alt text.
  final TextStyle style;

  /// Builds the image from [src] and [alt]; null shows the placeholder.
  final QuarkMarkdownImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final imageBuilder = this.imageBuilder;
    if (imageBuilder != null) return imageBuilder(context, src, alt);
    final quark = QuarkTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: quark.border),
        borderRadius: BorderRadius.circular(quark.radiusSm),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: quark.spacingSm,
          vertical: quark.spacingXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: quark.spacingXs,
          children: [
            Icon(
              QuarkIcons.image_outlined,
              size: (style.fontSize ?? 16) * 1.2,
              color: quark.mutedForeground,
            ),
            if (alt.isNotEmpty)
              Flexible(
                child: Text(
                  alt,
                  style: style.copyWith(color: quark.mutedForeground),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
