import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_tint_badge.dart';
import '../system/data_protection_level.dart';
import '../theme/quark_tokens.dart';

/// A data drive's backup state on its drive card: one chip tinted by
/// [level] that reads [label], and that opens to one line per backup copy.
///
/// [label] and [copies] are the caller's words ("Backed up Nov 2 · Backup A",
/// "Backup A · Nov 2"). With no [copies] the chip is a plain label. Expansion
/// is [expanded]; [onExpandedChanged] reports a tap on the chip with the
/// next open state.
///
/// Key prefixes: `drive_backup_chip_<id>` on the chip and
/// `drive_backup_copy_<id>_<index>` on each copy line.
///
/// ```dart
/// DriveBackupChip(
///   id: 'usb-1',
///   level: DataProtectionLevel.basic,
///   label: 'Backed up Nov 2 · Backup A',
///   copies: const ['Backup A · Nov 2'],
///   expanded: false,
///   onExpandedChanged: (open) {},
/// )
/// ```
class DriveBackupChip extends StatelessWidget {
  /// Creates the chip for the drive keyed [id].
  const DriveBackupChip({
    required this.id,
    required this.level,
    required this.label,
    required this.expanded,
    required this.onExpandedChanged,
    this.copies = const [],
    super.key,
  });

  /// Distinguishes this drive's keys from the others on the page.
  final String id;

  /// The drive's own level, which picks the tint.
  final DataProtectionLevel level;

  /// The words on the chip.
  final String label;

  /// One line per backup drive's copy, newest first. Empty draws no toggle.
  final List<String> copies;

  /// Whether the copy lines are open.
  final bool expanded;

  /// Called with the next open state when the chip is tapped.
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final color = dataProtectionLevelColor(tokens, level);
    final badge = QuarkTintBadge(label: label, color: color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (copies.isEmpty)
          KeyedSubtree(key: ValueKey('drive_backup_chip_$id'), child: badge)
        else
          TextButton(
            key: ValueKey('drive_backup_chip_$id'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.padded,
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => onExpandedChanged(!expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: badge),
                Icon(
                  expanded ? QuarkIcons.expand_less : QuarkIcons.expand_more,
                  size: 18,
                  color: color,
                ),
              ],
            ),
          ),
        if (expanded)
          for (var i = 0; i < copies.length; i++)
            Padding(
              padding: EdgeInsets.only(top: tokens.spacingXs),
              child: Text(
                copies[i],
                key: ValueKey('drive_backup_copy_${id}_$i'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.secondaryForeground,
                ),
              ),
            ),
      ],
    );
  }
}
