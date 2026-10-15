import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';
import '../quark_document_view.dart';

/// An image slot in a document preview, filled only by the caller.
class DocumentImageSlot extends StatelessWidget {
  /// Creates an image slot.
  const DocumentImageSlot({required this.image, this.imageBuilder, super.key});

  /// The image description and package part.
  final QuarkDocumentImage image;

  /// Builds an embedded image; null shows a placeholder.
  final QuarkDocumentImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final imageBuilder = this.imageBuilder;
    final canBuild = !image.external && image.part != null;
    if (canBuild && imageBuilder != null) {
      final width = image.width;
      final height = image.height;
      final built = imageBuilder(context, image);
      if (width != null && width > 0 && height != null && height > 0) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: AspectRatio(aspectRatio: width / height, child: built),
        );
      }
      return built;
    }

    final label = image.external
        ? image.alt.isEmpty
              ? 'External image not shown'
              : '${image.alt} (external image not shown)'
        : image.alt.isEmpty
        ? 'Image not available'
        : image.alt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: tokens.spacingSm,
          children: [
            Icon(
              image.external ? QuarkIcons.link_off : QuarkIcons.image_outlined,
              color: tokens.mutedForeground,
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
