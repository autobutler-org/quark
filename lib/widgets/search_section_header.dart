import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    final muted = QuarkTokens.of(context).mutedForeground;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
