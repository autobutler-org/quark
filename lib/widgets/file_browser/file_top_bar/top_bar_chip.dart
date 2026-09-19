import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A pill-shaped action in the file browser's top bar. When [iconOnly] the
/// label moves into the tooltip, which is how the bar survives a narrow
/// viewport without dropping the action.
class TopBarChip extends StatelessWidget {
  const TopBarChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.iconOnly = false,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool iconOnly;

  /// What the chip does, for a label that names a mode without explaining it
  /// (#2037). Falls back to [label] when the chip is icon-only, which is what
  /// keeps a narrow bar readable.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(QuarkColors.radiusLg);
    final iconColor = active
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Tooltip(
        message: tooltip ?? (iconOnly ? label : ''),
        child: Material(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline,
            ),
            borderRadius: radius,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: iconOnly
                  ? const EdgeInsets.all(8)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: iconOnly
                  ? Icon(icon, size: 16, color: iconColor)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: iconColor),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: active
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
