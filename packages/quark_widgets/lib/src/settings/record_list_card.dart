import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../layout/refresh_icon_button.dart';
import '../models/record_list_item.dart';

/// A settings card listing records the user acts on one at a time, such as
/// connected devices or signed-in sessions: a bold [title] over a
/// [subtitle], a [QuarkLoader] while [isLoading], an error row for [error],
/// then one row per record with a device icon and, where the record allows
/// it, a trailing [actionIcon] button.
///
/// [collapsible] folds the list under the title until the user opens it.
/// [onRefresh] adds a refresh button above the list, with the tooltip
/// "Refresh <title>", spinning while [isLoading]. [footer] goes under the
/// last row.
///
/// The caller decides what each part shows: the loader and the error row
/// appear whenever asked for, alongside whatever [records] holds, so a
/// caller that hides its rows while loading passes an empty list.
///
/// Key prefixes: `<keyPrefix>_tile_<id>` on each row and
/// `<keyPrefix>_<actionKey>_<id>` on its button, with [RecordListItem.id].
/// The refresh button is `refresh_button`.
///
/// ```dart
/// RecordListCard(
///   title: 'Sessions',
///   subtitle: 'Where your account is signed in',
///   keyPrefix: 'session',
///   actionKey: 'revoke',
///   actionIcon: QuarkIcons.logout,
///   actionTooltip: 'Sign out',
///   records: [
///     for (final s in sessions)
///       RecordListItem(id: s.id, title: s.name, subtitle: s.lastUsed),
///   ],
///   onAction: signOut,
/// );
/// ```
class RecordListCard extends StatelessWidget {
  /// Creates a card listing [records].
  const RecordListCard({
    required this.title,
    required this.subtitle,
    required this.records,
    required this.keyPrefix,
    required this.actionKey,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onAction,
    this.isLoading = false,
    this.error,
    this.emptyText,
    this.collapsible = false,
    this.onRefresh,
    this.footer,
    super.key,
  });

  /// The card's heading, drawn bold.
  final String title;

  /// The line under [title], such as a count or what the list is.
  final String subtitle;

  /// The rows, in order.
  final List<RecordListItem> records;

  /// Starts every row and button key: `<keyPrefix>_tile_<id>`.
  final String keyPrefix;

  /// Names the action in its button key: `<keyPrefix>_<actionKey>_<id>`.
  final String actionKey;

  /// The glyph on each row's action button.
  final IconData actionIcon;

  /// The tooltip on each row's action button.
  final String actionTooltip;

  /// Called with [RecordListItem.id] when a row's button is tapped. Null
  /// disables every button, for while an action is running.
  final ValueChanged<String>? onAction;

  /// Whether to show the loader.
  final bool isLoading;

  /// The sentence the error row shows, already written by the caller, or
  /// null for no error row.
  final String? error;

  /// The row shown when [records] is empty and nothing is loading or wrong.
  /// Null shows nothing.
  final String? emptyText;

  /// Whether the list starts folded under the title, opening on a tap.
  final bool collapsible;

  /// Reads the list again. Non-null adds a refresh button above the rows.
  final VoidCallback? onRefresh;

  /// Drawn under the last row, start-aligned with padding around it.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final onAction = this.onAction;
    final onRefresh = this.onRefresh;
    final footer = this.footer;
    final error = this.error;
    final emptyText = this.emptyText;
    final heading = Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final children = [
      if (onRefresh != null)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: RefreshIconButton(
              isRefreshing: isLoading,
              onPressed: onRefresh,
              tooltip: 'Refresh ${title.toLowerCase()}',
            ),
          ),
        ),
      if (isLoading)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: QuarkLoader(size: 20)),
        ),
      if (error != null)
        ListTile(
          leading: Icon(
            QuarkIcons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(error),
        ),
      if (records.isEmpty && !isLoading && error == null && emptyText != null)
        ListTile(title: Text(emptyText)),
      for (final record in records)
        ListTile(
          key: ValueKey('${keyPrefix}_tile_${record.id}'),
          leading: const Icon(QuarkIcons.devices),
          title: Text(record.title),
          subtitle: Text(record.subtitle),
          trailing: record.hasAction
              ? IconButton(
                  key: ValueKey('${keyPrefix}_${actionKey}_${record.id}'),
                  icon: Icon(actionIcon),
                  tooltip: actionTooltip,
                  onPressed: onAction == null
                      ? null
                      : () => onAction(record.id),
                )
              : null,
        ),
      if (footer != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.all(8), child: footer),
        ),
    ];
    return Card(
      child: collapsible
          ? ExpansionTile(
              title: heading,
              subtitle: Text(subtitle),
              children: children,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(title: heading, subtitle: Text(subtitle)),
                ...children,
              ],
            ),
    );
  }
}
