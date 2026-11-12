import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../registry.dart';

/// The left panel: a filter field over the registry, grouped and selectable.
///
/// Key prefix: `gallery_entry_<class name>` on every row.
class GalleryIndexPanel extends StatelessWidget {
  /// Creates the index showing the entries matching [filter].
  const GalleryIndexPanel({
    required this.filter,
    required this.selected,
    required this.onFilterChanged,
    required this.onSelected,
    super.key,
  });

  /// The lowercased filter text. Empty shows everything.
  final String filter;

  /// The entry currently shown in the example pane.
  final GalleryEntry selected;

  /// Called with the trimmed, lowercased text as the filter is typed.
  final ValueChanged<String> onFilterChanged;

  /// Called with the entry a row selects.
  final ValueChanged<GalleryEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final matches = registry
        .where(
          (e) =>
              filter.isEmpty ||
              e.name.toLowerCase().contains(filter) ||
              e.group.toLowerCase().contains(filter),
        )
        .toList();

    final groups = <String, List<GalleryEntry>>{};
    for (final entry in matches) {
      groups.putIfAbsent(entry.group, () => []).add(entry);
    }
    final groupNames = groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(tokens.spacingSm),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter widgets',
              isDense: true,
            ),
            onChanged: (value) => onFilterChanged(value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    'Nothing matches "$filter"',
                    style: TextStyle(color: tokens.mutedForeground),
                  ),
                )
              : ListView(
                  children: [
                    for (final group in groupNames) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          tokens.spacingMd,
                          tokens.spacingMd,
                          tokens.spacingMd,
                          tokens.spacingXs,
                        ),
                        child: Text(
                          group.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: tokens.primary,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ),
                      for (final entry in groups[group]!)
                        ListTile(
                          key: ValueKey('gallery_entry_${entry.name}'),
                          dense: true,
                          selected: entry.name == selected.name,
                          selectedTileColor: tokens.primary.withValues(
                            alpha: 0.12,
                          ),
                          title: Text(entry.name),
                          onTap: () => onSelected(entry),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
