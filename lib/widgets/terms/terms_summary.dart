import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One line of the plain-language summary above the terms.
typedef TermsSummaryPoint = ({IconData icon, String headline, String body});

/// The three things a new owner most needs to know, in the words they would
/// use, above the terms they are agreeing to (#2027).
///
/// Every point is a restatement of a section below it — data ownership from
/// §2, the absence of a warranty from §2 and §3, personal use and
/// responsibility from §1 and §4 — and each says so. A summary that invents a
/// promise the terms do not make would be worse than no summary at all, which
/// is why [kTermsSummaryDisclaimer] stays with them.
const List<TermsSummaryPoint> kTermsSummaryPoints = [
  (
    icon: QuarkIcons.home_rounded,
    headline: 'Your files stay on your Quark',
    body:
        'You own everything you put here, and by default it lives on hardware '
        'you control. Anything that leaves it — remote access, an import from '
        'another service — happens because you switched it on.',
  ),
  (
    icon: QuarkIcons.backup_outlined,
    headline: 'Keep your own backup',
    body:
        'Quark comes with no warranty and no promise about uptime or data '
        'integrity. Whatever you cannot afford to lose should exist somewhere '
        'else too.',
  ),
  (
    icon: QuarkIcons.person_outline,
    headline: "It's for your household",
    body:
        'Quark is for managing your own photos and files. What you store on '
        'it, and staying on the right side of the law while you do, is yours '
        'to answer for.',
  ),
];

/// What the summary is not.
const String kTermsSummaryDisclaimer =
    'A summary, not the agreement — the full terms below are what you accept.';

/// The plain-language card above the terms.
class TermsSummary extends StatelessWidget {
  /// Creates the summary card.
  const TermsSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('terms_summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In plain English',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final point in kTermsSummaryPoints) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(point.icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        point.headline,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        point.body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (point != kTermsSummaryPoints.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          Text(
            kTermsSummaryDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
