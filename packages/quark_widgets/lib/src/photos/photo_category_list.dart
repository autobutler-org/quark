import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/photo_category_entry.dart';

/// The "Showing" picker in a photo sidebar: the category being shown and its
/// count, which expands into every category to choose from.
///
/// Whether it is expanded is the caller's state, [expanded] in and
/// [onToggleExpanded] out, so choosing a category can collapse it again.
///
/// Key prefixes: `photo_category_toggle` on the "Showing" row, and
/// `photo_category_<id>` on each category row, rendered only while [expanded].
///
/// ```dart
/// PhotoCategoryList(
///   categories: controller.categories,
///   selectedId: controller.selectedCategoryId,
///   expanded: controller.categoriesExpanded,
///   onToggleExpanded: controller.toggleCategoriesExpanded,
///   onSelected: controller.selectCategory,
/// );
/// ```
class PhotoCategoryList extends StatelessWidget {
  /// Creates the picker over [categories].
  const PhotoCategoryList({
    required this.categories,
    required this.selectedId,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelected,
    super.key,
  });

  /// Every category, in the order they are listed.
  final List<PhotoCategoryEntry> categories;

  /// The [PhotoCategoryEntry.id] being shown. Summarized on the "Showing" row
  /// and checked in the list.
  final String selectedId;

  /// Whether the category rows are showing.
  final bool expanded;

  /// Called when the "Showing" row is tapped.
  final VoidCallback onToggleExpanded;

  /// Called with the [PhotoCategoryEntry.id] of the row that was tapped.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = categories.where((c) => c.id == selectedId).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('photo_category_toggle'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Showing'),
          subtitle: selected == null
              ? null
              : Text('${selected.label}: ${selected.count}'),
          trailing: Icon(
            expanded ? QuarkIcons.expand_less : QuarkIcons.expand_more,
          ),
          onTap: onToggleExpanded,
        ),
        if (expanded)
          for (final category in categories)
            ListTile(
              key: ValueKey('photo_category_${category.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              onTap: () => onSelected(category.id),
              leading: Icon(
                category.icon,
                color: category.id == selectedId
                    ? theme.colorScheme.primary
                    : null,
              ),
              title: Text(
                '${category.label}: ${category.count}',
                style: theme.textTheme.titleMedium,
              ),
              trailing: category.id == selectedId
                  ? const Icon(QuarkIcons.check, size: 16)
                  : null,
            ),
      ],
    );
  }
}
