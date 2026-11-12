import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';

/// One option's share of a poll's answers: a bar filled to [count] out of
/// [total], with the count and the percentage beside it.
///
/// A part of `QuarkPollCard`, tested through it.
class PollOptionTally extends StatelessWidget {
  /// Creates the tally of [count] answers out of [total].
  const PollOptionTally({required this.count, required this.total, super.key});

  /// How many answers picked the option.
  final int count;

  /// How many people answered. Zero draws an empty bar.
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final share = total == 0 ? 0.0 : count / total;
    return Row(
      spacing: tokens.spacingSm,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              color: tokens.primary,
              backgroundColor: tokens.border,
            ),
          ),
        ),
        Text(
          '$count · ${(share * 100).round()}%',
          style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
        ),
      ],
    );
  }
}
