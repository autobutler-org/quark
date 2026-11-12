import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// What a fire, a theft, or a failed drive does to one copy of the files
/// versus three, and the reminder to keep one backup drive somewhere else.
///
/// The sheet is static. It does not animate, and it does not know how
/// protected this Quark is. Show it in a sheet titled "Why two backup
/// drives?". Closing that sheet dismisses it; the protection card opens it
/// again.
///
/// Key prefixes: `data_protection_explainer` on the column,
/// `data_protection_explainer_one` and `data_protection_explainer_three` on
/// the two cases, and `data_protection_explainer_tip` on the reminder.
///
/// ```dart
/// showQuarkSheet<void>(
///   context,
///   title: 'Why two backup drives?',
///   builder: (_) => const DataProtectionExplainerSheet(),
/// );
/// ```
class DataProtectionExplainerSheet extends StatelessWidget {
  /// Creates the explainer.
  const DataProtectionExplainerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.cardForeground,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: tokens.secondaryForeground,
    );

    return Column(
      key: const ValueKey('data_protection_explainer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A fire, a theft, or a failed drive.',
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.cardForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: tokens.spacingMd),
        for (final scenario in _scenarios) ...[
          Text(
            scenario.title,
            key: ValueKey('data_protection_explainer_${scenario.id}'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: tokens.cardForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: tokens.spacingSm),
          Wrap(
            spacing: tokens.spacingSm,
            runSpacing: tokens.spacingSm,
            children: [
              for (final copy in scenario.copies)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (scenario.survives ? tokens.success : tokens.error)
                        .withValues(alpha: 0.12),
                    border: Border.all(
                      color: scenario.survives ? tokens.success : tokens.error,
                    ),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacingSm,
                      vertical: tokens.spacingXs,
                    ),
                    child: Text(copy, style: muted),
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.spacingSm),
          Text(scenario.outcome, style: body),
          SizedBox(height: tokens.spacingLg),
        ],
        DecoratedBox(
          key: const ValueKey('data_protection_explainer_tip'),
          decoration: BoxDecoration(
            color: tokens.sidebar,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Text(
              'Keep one backup drive somewhere else, such as a relative\'s '
              'house, the office, or a box that can survive a fire, and '
              'rotate it in.',
              style: body,
            ),
          ),
        ),
      ],
    );
  }
}

class _Scenario {
  const _Scenario({
    required this.id,
    required this.title,
    required this.copies,
    required this.outcome,
    required this.survives,
  });

  final String id;
  final String title;
  final List<String> copies;
  final String outcome;
  final bool survives;
}

const _scenarios = [
  _Scenario(
    id: 'one',
    title: 'One copy',
    copies: ['Quark'],
    outcome: 'A fire, a theft, or a failed drive takes everything.',
    survives: false,
  ),
  _Scenario(
    id: 'three',
    title: 'Three copies',
    copies: ['Quark', 'Backup drive', 'Kept somewhere else'],
    outcome:
        'A fire or theft at home leaves the drive you keep somewhere else. '
        'A failed drive leaves the other two.',
    survives: true,
  ),
];
