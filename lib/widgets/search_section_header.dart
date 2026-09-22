import 'package:flutter/material.dart';

/// The small label that opens a group of search results in the docs and
/// sheets lists, such as "Content matches" or "In Docs".
class SearchSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const SearchSectionHeader({
    required this.icon,
    required this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
