import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// One label and value in `QuarkDocumentProperties`.
class DocumentPropertyRow extends StatelessWidget {
  /// Creates a property row.
  const DocumentPropertyRow({
    required this.label,
    required this.value,
    super.key,
  });

  /// The property name.
  final String label;

  /// The formatted property value.
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.secondaryForeground,
              ),
            ),
          ),
          SizedBox(width: tokens.spacingMd),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
