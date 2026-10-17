import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../theme/quark_tokens.dart';

/// The bar under a `DuplicateGroupList` while copies are marked: how many
/// copies in how many groups, so marks scrolled out of view are still
/// counted out loud, a Clear button, and the delete button.
///
/// The list shows it only once something is marked (#3362), so it never
/// offers a delete the user did not set up.
///
/// Key prefixes: `duplicates_selection_summary` on the count,
/// `duplicates_clear_selection` on Clear, and `duplicates_delete` on the
/// delete button.
///
/// ```dart
/// DuplicateDeleteBar(
///   count: 5,
///   groupCount: 4,
///   onDelete: confirmAndDelete,
///   onClear: controller.clearSelection,
/// );
/// ```
class DuplicateDeleteBar extends StatelessWidget {
  /// Creates the bar for [count] copies across [groupCount] groups.
  const DuplicateDeleteBar({
    required this.count,
    required this.groupCount,
    required this.onDelete,
    this.onClear,
    this.isDeleting = false,
    super.key,
  });

  /// How many copies are marked for deletion.
  final int count;

  /// How many groups those copies are in.
  final int groupCount;

  /// Called when the delete button is tapped.
  final VoidCallback onDelete;

  /// Called when Clear is tapped. Null hides it.
  final VoidCallback? onClear;

  /// Whether a delete is running, which busies the delete button and
  /// disables Clear.
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onClear = this.onClear;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.background,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$count ${count == 1 ? 'copy' : 'copies'} in '
                      '$groupCount ${groupCount == 1 ? 'group' : 'groups'}',
                      key: const ValueKey('duplicates_selection_summary'),
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ),
                  if (onClear != null)
                    TextButton(
                      key: const ValueKey('duplicates_clear_selection'),
                      onPressed: isDeleting ? null : onClear,
                      child: const Text('Clear'),
                    ),
                ],
              ),
              SizedBox(height: tokens.spacingSm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('duplicates_delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.error,
                    foregroundColor: tokens.errorForeground,
                  ),
                  onPressed: isDeleting ? null : onDelete,
                  icon: isDeleting
                      ? const QuarkLoader(size: 20)
                      : const Icon(QuarkIcons.delete_outline),
                  label: Text(
                    'Delete $count ${count == 1 ? 'photo' : 'photos'}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
