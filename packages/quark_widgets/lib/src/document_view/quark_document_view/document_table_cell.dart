import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';
import '../quark_document_view.dart';
import 'document_block.dart';

/// One bordered cell in a document table.
class DocumentTableCellView extends StatelessWidget {
  /// Creates a table cell.
  const DocumentTableCellView({
    required this.cell,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The cell and its nested blocks.
  final QuarkDocumentTableCell cell;

  /// The document body style.
  final TextStyle style;

  /// Called with a link target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Builds embedded images in this cell.
  final QuarkDocumentImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: tokens.border)),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: tokens.spacingSm,
          children: [
            for (final block in cell.blocks)
              DocumentBlockView(
                block: block,
                style: style,
                onLinkTap: onLinkTap,
                imageBuilder: imageBuilder,
              ),
          ],
        ),
      ),
    );
  }
}
