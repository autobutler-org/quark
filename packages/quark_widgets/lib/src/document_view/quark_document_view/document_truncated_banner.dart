import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../quark_document.dart';

/// The notice shown when a document preview stopped at a safety limit.
class DocumentTruncatedBanner extends StatelessWidget {
  /// Creates a truncation notice from [summary].
  const DocumentTruncatedBanner({required this.summary, super.key});

  /// Counts for the rendered portion of the document.
  final QuarkDocumentSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final pages = summary.pages;
    return DecoratedBox(
      key: const ValueKey('document_truncated_banner'),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(bottom: BorderSide(color: tokens.warning)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingLg,
          vertical: tokens.spacingSm,
        ),
        child: Row(
          spacing: tokens.spacingSm,
          children: [
            Icon(QuarkIcons.warning_amber, color: tokens.warning),
            Expanded(
              child: Text(
                pages == null
                    ? 'This preview stops at the document limit.'
                    : 'Showing the first $pages pages.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
