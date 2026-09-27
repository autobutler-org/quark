import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../new_file_dialog.dart';

/// One selectable file type in [NewFileDialog]'s type picker.
///
/// Key prefix: `new_file_type_<extension without the dot, or `generic`>`.
class NewFileTypeCard extends StatelessWidget {
  /// Creates the card offering [type].
  const NewFileTypeCard({
    required this.type,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  /// The type this card offers.
  final NewFileType type;

  /// Whether this is the type the dialog currently has selected.
  final bool isSelected;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final slug = type.extension.isEmpty
        ? 'generic'
        : type.extension.substring(1);
    // The selected border is a pixel thicker, and a border insets the content,
    // so the padding gives that pixel back rather than nudging the icon and
    // label every time the selection moves.
    final borderWidth = isSelected ? 2.0 : 1.0;
    final inset = borderWidth - 1;

    return GestureDetector(
      key: ValueKey('new_file_type_$slug'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 88,
        padding: EdgeInsets.symmetric(
          vertical: tokens.spacingSm + tokens.spacingXs - inset,
          horizontal: tokens.spacingSm - inset,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: borderWidth,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              size: 28,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            SizedBox(height: tokens.spacingXs + tokens.spacingXs / 2),
            Text(
              type.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
