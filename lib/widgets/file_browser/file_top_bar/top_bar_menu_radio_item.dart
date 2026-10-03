import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One of a set of mutually exclusive choices in the top bar's Views menu. The
/// unselected rows still reserve the tick's width so the labels do not shift
/// as the choice moves.
///
/// The row is 48dp tall, and a screen reader hears whether it is the chosen
/// one (#2603, #2605).
class TopBarMenuRadioItem extends StatelessWidget {
  const TopBarMenuRadioItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 18,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: selected
            ? Icon(
                QuarkIcons.check_rounded,
                size: 16,
                color: colorScheme.primary,
              )
            : const SizedBox(width: 16),
        onTap: onTap,
      ),
    );
  }
}
