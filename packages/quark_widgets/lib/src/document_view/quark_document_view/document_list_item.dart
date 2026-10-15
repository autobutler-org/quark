import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';
import 'document_run_text.dart';

/// One indented ordered or unordered document list item.
class DocumentListItem extends StatelessWidget {
  /// Creates a list item.
  const DocumentListItem({
    required this.item,
    required this.style,
    this.onLinkTap,
    super.key,
  });

  /// The item to render.
  final QuarkDocumentListItem item;

  /// The body text style.
  final TextStyle style;

  /// Called with a link target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(left: tokens.spacingLg * item.level.clamp(0, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: tokens.spacingLg,
            child: Text(
              item.marker,
              textAlign: TextAlign.end,
              style: style.copyWith(color: tokens.secondaryForeground),
            ),
          ),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: DocumentRunText(
              runs: item.runs,
              style: style,
              onLinkTap: onLinkTap,
            ),
          ),
        ],
      ),
    );
  }
}
