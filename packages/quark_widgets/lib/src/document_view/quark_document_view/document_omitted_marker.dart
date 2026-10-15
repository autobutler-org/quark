import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// A notice for document content the safe preview intentionally left out.
class DocumentOmittedMarker extends StatelessWidget {
  /// Creates an omitted-content notice.
  const DocumentOmittedMarker({required this.what, super.key});

  /// A short name for the omitted content.
  final String what;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Row(
          spacing: tokens.spacingSm,
          children: [
            Icon(QuarkIcons.info_outline, color: tokens.secondaryForeground),
            Expanded(
              child: Text(
                '$what not shown',
                style: TextStyle(color: tokens.secondaryForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
