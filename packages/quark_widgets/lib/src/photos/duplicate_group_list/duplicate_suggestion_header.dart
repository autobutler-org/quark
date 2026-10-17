import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// The row above a `DuplicateGroupList`'s groups offering to mark the
/// suggested copies in one tap: every identical copy but one (#3362).
///
/// An outlined button, not a red one, because it only marks: deleting still
/// takes the delete bar and its confirmation.
///
/// Key prefix: `duplicates_select_suggested` on the button.
///
/// ```dart
/// DuplicateSuggestionHeader(onSelectSuggested: controller.selectSuggested);
/// ```
class DuplicateSuggestionHeader extends StatelessWidget {
  /// Creates the header.
  const DuplicateSuggestionHeader({required this.onSelectSuggested, super.key});

  /// Called when Select suggested is tapped.
  final VoidCallback onSelectSuggested;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Wrap(
      spacing: tokens.spacingMd,
      runSpacing: tokens.spacingSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('duplicates_select_suggested'),
          onPressed: onSelectSuggested,
          icon: const Icon(QuarkIcons.check_circle_outline, size: 18),
          label: const Text('Select suggested'),
        ),
        Text(
          'Marks every identical copy except one. Similar photos are left '
          'for you to check.',
          style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
        ),
      ],
    );
  }
}
