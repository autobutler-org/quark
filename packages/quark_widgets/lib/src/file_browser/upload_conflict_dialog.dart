import 'package:flutter/material.dart';

/// Asks what to do about an upload whose name is already in use.
///
/// The Quark refuses such an upload rather than renaming it on its own, so
/// this is where the user picks: keep both, which lands the new file under a
/// free name, or replace, which overwrites the file that is there. Cancel
/// leaves both alone.
///
/// Data in, callbacks out: the choice travels through [onKeepBoth],
/// [onReplace] and [onCancel], and the dialog never closes itself — the caller
/// that pushed it pops it. [applyToAll] is the caller's state too; show the
/// checkbox with [showApplyToAll] when more files are still to go, and keep
/// the value with [onApplyToAllChanged].
///
/// Key prefixes: `upload_conflict_keep_both`, `upload_conflict_replace`,
/// `upload_conflict_cancel` and `upload_conflict_apply_to_all`.
///
/// ```dart
/// showDialog<UploadConflictOutcome>(
///   context: context,
///   builder: (ctx) => UploadConflictDialog(
///     fileName: 'holiday.jpg',
///     onKeepBoth: () => Navigator.of(ctx).pop(UploadConflictOutcome.keepBoth),
///     onReplace: () => Navigator.of(ctx).pop(UploadConflictOutcome.replace),
///     onCancel: () => Navigator.of(ctx).pop(null),
///   ),
/// );
/// ```
class UploadConflictDialog extends StatelessWidget {
  /// Creates the dialog for the clash on [fileName].
  const UploadConflictDialog({
    required this.fileName,
    required this.onKeepBoth,
    required this.onReplace,
    required this.onCancel,
    this.showApplyToAll = false,
    this.applyToAll = false,
    this.onApplyToAllChanged,
    super.key,
  });

  /// The name the upload wanted, which something else already has.
  final String fileName;

  /// Whether to offer applying the choice to the rest of the upload.
  final bool showApplyToAll;

  /// Whether that offer is ticked.
  final bool applyToAll;

  /// Called with the new value when the offer is ticked or cleared.
  final ValueChanged<bool>? onApplyToAllChanged;

  /// Called when the user wants both files kept.
  final VoidCallback onKeepBoth;

  /// Called when the user wants the file that is there replaced.
  final VoidCallback onReplace;

  /// Called when the user wants neither: this file is not uploaded.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final onApplyToAllChanged = this.onApplyToAllChanged;

    return AlertDialog(
      title: const Text('That name is taken'),
      // Scrollable, so a long name and a short screen still leave every
      // button reachable rather than overflowing.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$fileName" is already in this folder. Keep both, and the new '
              'one gets a number after its name, or replace what is there?',
            ),
            if (showApplyToAll)
              CheckboxListTile(
                key: const ValueKey('upload_conflict_apply_to_all'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: applyToAll,
                onChanged: onApplyToAllChanged == null
                    ? null
                    : (value) => onApplyToAllChanged(value ?? false),
                title: const Text('Do the same for the rest of this upload'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('upload_conflict_cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('upload_conflict_replace'),
          onPressed: onReplace,
          child: const Text('Replace'),
        ),
        FilledButton(
          key: const ValueKey('upload_conflict_keep_both'),
          onPressed: onKeepBoth,
          child: const Text('Keep both'),
        ),
      ],
    );
  }
}
