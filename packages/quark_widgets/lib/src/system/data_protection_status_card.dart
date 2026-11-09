import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'data_protection_level.dart';
import 'data_protection_meter.dart';

/// The protection card: the level the Quark reported for the whole Quark,
/// its sentence, one next step, and **Back up now**.
///
/// [level] is shown as given. [sentence] and [nextStepLabel] are the
/// caller's words. [onNextStep] is the deep link; null draws no button,
/// which is how a non-admin sees no drive action. [onBackUpNow] starts a
/// backup onto every connected backup drive; null draws no button.
/// [onExplain] opens the "Why two backup drives?" sheet again. Each drive's
/// own state is on its drive card, not here.
///
/// While [isLoading] is true and [level] is null, the card is a
/// [QuarkLoader]. [error] is rendered as given. The card never composes an
/// error sentence.
///
/// Key prefixes: `data_protection_card` on the frame,
/// `data_protection_loading` on the loader, `data_protection_error` on the
/// error line, `data_protection_sentence` on the sentence,
/// `data_protection_next_step` on the next step,
/// `data_protection_back_up_now` on Back up now, and
/// `data_protection_explain` on the explainer button.
///
/// ```dart
/// DataProtectionStatusCard(
///   level: DataProtectionLevel.basic,
///   sentence:
///       'Your files are on 2 drives. Add a second backup drive and keep it somewhere else.',
///   nextStepLabel: 'Assign the backup role',
///   onNextStep: assignRole,
///   onBackUpNow: backUpNow,
///   onExplain: showExplainer,
/// )
/// ```
class DataProtectionStatusCard extends StatelessWidget {
  /// Creates a card for [level], or a loader or error when [level] is null.
  const DataProtectionStatusCard({
    this.level,
    this.sentence,
    this.nextStepLabel,
    this.onNextStep,
    this.onBackUpNow,
    this.onExplain,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The level the Quark reported. Null before the first answer.
  final DataProtectionLevel? level;

  /// The Quark's one sentence. Ignored while [level] is null.
  final String? sentence;

  /// The label of the one next step. Null, or a null [onNextStep], draws no
  /// button.
  final String? nextStepLabel;

  /// Called when the next step is tapped. Null draws no button.
  final VoidCallback? onNextStep;

  /// Called when Back up now is tapped. Null draws no button.
  final VoidCallback? onBackUpNow;

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
    final onBackUpNow = this.onBackUpNow;
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
      if (onBackUpNow != null) {
        children.add(
          OutlinedButton(
            key: const ValueKey('data_protection_back_up_now'),
            onPressed: onBackUpNow,
            child: const Text('Back up now', textAlign: TextAlign.center),
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
