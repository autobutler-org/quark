import 'package:flutter/material.dart';

import '../core/quark_tint_badge.dart';
import '../theme/quark_tokens.dart';
import 'drive_health_verdict.dart';

/// Asks before a drive in poor health is committed to.
///
/// The caller decides when to show it. [requiresAcknowledgment] is a Replace
/// soon drive: confirming is the acknowledgment, and the confirm button says
/// so. A stronger warning ([strongerWarning]) is default storage moving to a
/// drive the Quark marked as worse than the current one. Watch and Unknown
/// use Continue and do not ask for an acknowledgment.
///
/// [reason] is the Quark's sentence, shown unchanged. [addsBackup] adds that
/// a backup is placed beside files already on the drive. [keepsExistingFiles]
/// says those files stay. Neither sentence names a manufacture year.
///
/// The dialog does not close itself. [onConfirm] and [onCancel] fire, and
/// the caller that pushed it pops it.
///
/// Key prefixes: `drive_health_ack_confirm`, `drive_health_ack_cancel`,
/// `drive_health_ack_reason`, `drive_health_ack_warning`, and
/// `drive_health_ack_files`. The badge uses `drive_health_badge`. When [id]
/// is set, the acknowledgment keys become `drive_health_ack_<id>_<suffix>`
/// and the badge key becomes `drive_health_badge_<id>`.
///
/// ```dart
/// DriveHealthAcknowledgment(
///   verdict: DriveHealthVerdict.replaceSoon,
///   reason: 'This spinning drive is heavily used.',
///   requiresAcknowledgment: true,
///   keepsExistingFiles: true,
///   addsBackup: true,
///   onConfirm: () {},
///   onCancel: () {},
/// )
/// ```
class DriveHealthAcknowledgment extends StatelessWidget {
  /// Creates the acknowledgment for [verdict].
  const DriveHealthAcknowledgment({
    required this.verdict,
    required this.onConfirm,
    required this.onCancel,
    this.reason,
    this.strongerWarning = false,
    this.requiresAcknowledgment = false,
    this.keepsExistingFiles = false,
    this.addsBackup = false,
    this.id,
    super.key,
  });

  /// The verdict the Quark reported. Its word is drawn, not its color alone.
  final DriveHealthVerdict verdict;

  /// The Quark's one-sentence reason. Null or blank draws no sentence.
  final String? reason;

  /// Whether default storage would move to a worse drive.
  final bool strongerWarning;

  /// Whether confirming must send the acknowledgment flag.
  ///
  /// True for Replace soon. The confirm button then reads
  /// "Use this drive anyway".
  final bool requiresAcknowledgment;

  /// Whether to say that files already on the drive stay.
  final bool keepsExistingFiles;

  /// Whether to say that the backup is added beside those files.
  final bool addsBackup;

  /// Distinguishes keys when [id] is set. Null uses the prefixes with no id.
  final String? id;

  /// Called when the confirm button is tapped.
  final VoidCallback onConfirm;

  /// Called when Cancel is tapped.
  final VoidCallback onCancel;

  String _key(String suffix) {
    final id = this.id;
    if (id == null || id.isEmpty) return 'drive_health_ack_$suffix';
    return 'drive_health_ack_${id}_$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final reason = this.reason?.trim();
    final files = addsBackup
        ? 'Files already on this drive stay. The backup is added beside them.'
        : keepsExistingFiles
        ? 'Files already on this drive stay.'
        : null;

    return AlertDialog(
      scrollable: true,
      title: Text(
        strongerWarning
            ? 'This drive is in worse shape'
            : requiresAcknowledgment
            ? 'Replace this drive soon?'
            : 'Look at this drive first',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuarkTintBadge(
            key: ValueKey(
              id?.isNotEmpty == true
                  ? 'drive_health_badge_$id'
                  : 'drive_health_badge',
            ),
            label: verdict.label,
            color: driveHealthVerdictColor(tokens, verdict),
            semanticLabel: '${verdict.label} drive health',
          ),
          if (reason != null && reason.isNotEmpty) ...[
            SizedBox(height: tokens.spacingSm),
            Text(reason, key: ValueKey(_key('reason'))),
          ],
          if (strongerWarning) ...[
            SizedBox(height: tokens.spacingSm),
            Text(
              'This drive is in worse health than the current default storage.',
              key: ValueKey(_key('warning')),
            ),
          ],
          if (requiresAcknowledgment) ...[
            SizedBox(height: tokens.spacingSm),
            const Text(
              'Continuing acknowledges that this drive should be replaced soon.',
            ),
          ],
          if (files != null) ...[
            SizedBox(height: tokens.spacingSm),
            Text(files, key: ValueKey(_key('files'))),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: ValueKey(_key('cancel')),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey(_key('confirm')),
          style: requiresAcknowledgment
              ? FilledButton.styleFrom(
                  backgroundColor: tokens.error,
                  foregroundColor: tokens.errorForeground,
                )
              : null,
          onPressed: onConfirm,
          child: Text(
            requiresAcknowledgment ? 'Use this drive anyway' : 'Continue',
          ),
        ),
      ],
    );
  }
}
