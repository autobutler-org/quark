import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';
import '../quark_document_view.dart';
import 'document_image_slot.dart';
import 'document_list_item.dart';
import 'document_omitted_marker.dart';
import 'document_run_text.dart';
import 'document_table.dart';

/// One block in a `QuarkDocumentView`.
class DocumentBlockView extends StatelessWidget {
  /// Creates a view for [block].
  const DocumentBlockView({
    required this.block,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The block to render.
  final QuarkDocumentBlock block;

  /// The document body style.
  final TextStyle style;

  /// Called with a link target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Builds an embedded image without letting the view load it itself.
  final QuarkDocumentImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final block = this.block;
    return switch (block) {
      QuarkDocumentParagraph() => DocumentRunText(
        runs: block.runs,
        style: style,
        textAlign: switch (block.alignment) {
          QuarkDocumentAlignment.left => TextAlign.left,
          QuarkDocumentAlignment.center => TextAlign.center,
          QuarkDocumentAlignment.right => TextAlign.right,
          QuarkDocumentAlignment.justify => TextAlign.justify,
        },
        onLinkTap: onLinkTap,
      ),
      QuarkDocumentHeading() => Padding(
        padding: EdgeInsets.only(top: tokens.spacingSm),
        child: Semantics(
          header: true,
          child: DocumentRunText(
            runs: block.runs,
            style:
                switch (block.level) {
                  1 => textTheme.headlineMedium,
                  2 => textTheme.headlineSmall,
                  3 => textTheme.titleLarge,
                  4 => textTheme.titleMedium,
                  _ => textTheme.titleSmall,
                }?.copyWith(
                  color: block.level == 6
                      ? tokens.mutedForeground
                      : tokens.foreground,
                  fontWeight: FontWeight.w600,
                ) ??
                style,
            onLinkTap: onLinkTap,
          ),
        ),
      ),
      QuarkDocumentListItem() => DocumentListItem(
        item: block,
        style: style,
        onLinkTap: onLinkTap,
      ),
      QuarkDocumentTable() => DocumentTableView(
        table: block,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
      QuarkDocumentImage() => DocumentImageSlot(
        image: block,
        imageBuilder: imageBuilder,
      ),
      QuarkDocumentOmitted() => DocumentOmittedMarker(what: block.what),
      QuarkDocumentPageBreak() => Row(
        children: [
          Expanded(child: Divider(color: tokens.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Text(
              'Page break',
              style: textTheme.labelSmall?.copyWith(
                color: tokens.mutedForeground,
              ),
            ),
          ),
          Expanded(child: Divider(color: tokens.border)),
        ],
      ),
    };
  }
}
