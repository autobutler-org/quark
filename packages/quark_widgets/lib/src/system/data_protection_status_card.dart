import 'package:flutter/material.dart';

import '../calendar/calendar_labels.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'data_protection_drive.dart';
import 'data_protection_level.dart';
import 'data_protection_meter.dart';

/// The protection card: the level the Quark reported, its sentence, each
/// backup drive's last backup, and one next step.
///
/// [level] is shown as given. Drives that do not count still do not change
/// it. [sentence] and [nextStepLabel] are the caller's words. [onNextStep]
/// is the deep link; null draws no button, which is how a non-admin sees no
/// drive action. [onExplain] opens the "Why two backup drives?" sheet again.
///
/// While [isLoading] is true and [level] is null, the card is a
/// [QuarkLoader]. [error] is rendered as given. The card never composes an
/// error sentence.
///
/// Key prefixes: `data_protection_card` on the frame,
/// `data_protection_loading` on the loader, `data_protection_error` on the
/// error line, `data_protection_sentence` on the sentence,
/// `data_protection_next_step` on the next step, `data_protection_explain`
/// on the explainer button, and `data_protection_drive_<id>`,
/// `data_protection_drive_<id>_backed_up`, and
/// `data_protection_drive_<id>_reason` on each drive.
///
/// ```dart
/// DataProtectionStatusCard(
///   level: DataProtectionLevel.basic,
///   sentence:
///       'Your files are on 2 drives. Add a second backup drive and keep it somewhere else.',
///   nextStepLabel: 'Assign the backup role',
///   onNextStep: assignRole,
///   onExplain: showExplainer,
/// )
/// ```
class DataProtectionStatusCard extends StatelessWidget {
  /// Creates a card for [level], or a loader or error when [level] is null.
  const DataProtectionStatusCard({
    this.level,
    this.sentence,
    this.drives = const [],
    this.nextStepLabel,
    this.onNextStep,
    this.onExplain,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The level the Quark reported. Null before the first answer.
  final DataProtectionLevel? level;

  /// The Quark's one sentence. Ignored while [level] is null.
  final String? sentence;

  /// Backup drives, in the order the caller lists them.
  final List<DataProtectionDrive> drives;

  /// The label of the one next step. Null, or a null [onNextStep], draws no
  /// button.
  final String? nextStepLabel;

  /// Called when the next step is tapped. Null draws no button.
  final VoidCallback? onNextStep;

  /// Called when "Why two backup drives?" is tapped. Null hides that button.
  final VoidCallback? onExplain;

  /// Whether the first load is still in flight. A later refresh keeps [level]
  /// on screen.
  final bool isLoading;

  /// The error sentence the caller built. Null draws none.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final level = this.level;
    final onExplain = this.onExplain;
    final onNextStep = this.onNextStep;
    final nextStepLabel = this.nextStepLabel;
    final error = this.error;
    final sentence = this.sentence;

    final children = <Widget>[];
    if (level == null && isLoading) {
      children.add(
        const SizedBox(
          height: 48,
          child: Center(
            child: QuarkLoader(
              key: ValueKey('data_protection_loading'),
              size: 20,
            ),
          ),
        ),
      );
    } else if (level == null) {
      children.add(
        Text(
          error ?? '',
          key: const ValueKey('data_protection_error'),
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.error),
        ),
      );
    } else {
      children.add(DataProtectionMeter(level: level));
      if (sentence != null) {
        children.add(
          Text(
            sentence,
            key: const ValueKey('data_protection_sentence'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.cardForeground,
            ),
          ),
        );
      }
      for (final drive in drives) {
        children.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                drive.name,
                key: ValueKey('data_protection_drive_${drive.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.cardForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (drive.lastBackedUp != null)
                Text(
                  'Last backed up ${_formatBackedUp(drive.lastBackedUp!)}',
                  key: ValueKey('data_protection_drive_${drive.id}_backed_up'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryForeground,
                  ),
                ),
              if (drive.reason != null && drive.reason!.isNotEmpty)
                Text(
                  drive.reason!,
                  key: ValueKey('data_protection_drive_${drive.id}_reason'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.mutedForeground,
                  ),
                ),
            ],
          ),
        );
      }
      if (error != null) {
        children.add(
          Text(
            error,
            key: const ValueKey('data_protection_error'),
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.error),
          ),
        );
      }
      if (nextStepLabel != null && onNextStep != null) {
        children.add(
          FilledButton(
            key: const ValueKey('data_protection_next_step'),
            onPressed: onNextStep,
            child: Text(nextStepLabel, textAlign: TextAlign.center),
          ),
        );
      }
    }
    if (onExplain != null && !(level == null && isLoading)) {
      children.add(
        TextButton(
          key: const ValueKey('data_protection_explain'),
          onPressed: onExplain,
          child: const Text(
            'Why two backup drives?',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return DecoratedBox(
      key: const ValueKey('data_protection_card'),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: tokens.spacingSm),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBackedUp(DateTime time) {
  final local = time.toLocal();
  return '${CalendarLabels.month(local.month)} ${local.day}, ${local.year}';
}
