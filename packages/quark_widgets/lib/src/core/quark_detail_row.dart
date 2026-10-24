import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// One labeled field in a details panel: a muted [label] over its [value],
/// with any [actions] beside the value. A saved login's fields and a drive's
/// health readings are both drawn with it.
///
/// It prints [value] as it is given. It is not exported: the vault entry
/// details and the drive health detail are its callers, and each decides
/// which fields exist.
///
/// Key prefixes: none of its own. A caller keys the row through `key`, such
/// as `drive_health_row_<field>`.
///
/// ```dart
/// QuarkDetailRow(
///   label: 'Username',
///   value: entry.username,
///   selectable: true,
///   actions: [copyButton],
/// );
/// ```
class QuarkDetailRow extends StatelessWidget {
  /// Creates a row named [label] showing [value].
  const QuarkDetailRow({
    required this.label,
    required this.value,
    this.actions = const [],
    this.selectable = false,
    super.key,
  });

  /// What the field is, such as "Power-on hours".
  final String label;

  /// What it shows, already in words, which may be a mask.
  final String value;

  /// Buttons beside the value, such as copy.
  final List<Widget> actions;

  /// Whether a long press selects the value. A selectable value is a target
  /// like the buttons beside it, so it gets the same 48dp height.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.secondaryForeground,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: selectable
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: kMinInteractiveDimension,
                        ),
                        child: SelectableText(value, style: style),
                      )
                    : Text(value, style: style),
              ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}
