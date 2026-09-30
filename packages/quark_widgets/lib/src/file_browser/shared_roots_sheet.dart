import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/shared_root_item.dart';
import '../layout/quark_sheet.dart';

/// The body of a bottom sheet for opening one of the folders somebody else
/// shared with the signed-in account.
///
/// Ad-hoc shares land wherever their owner keeps them, so there is no one
/// folder holding them all. The sheet is that list: each entry names the
/// shared item and who owns it, and tapping one hands its path back through
/// [onPicked]. It never loads — the caller has the [items] already — and a
/// caller with none to show opens no sheet at all. Show it with
/// [showQuarkSheet], which gives it its title, close button and height cap
/// (#2585).
///
/// Key prefixes: `shared_root_<path>` on each entry.
///
/// ```dart
/// showQuarkSheet<String>(
///   context,
///   title: 'Shared with me',
///   builder: (context) => SharedRootsSheet(
///     items: const [
///       SharedRootItem(path: 'users/alice/Trip', name: 'Trip', owner: 'alice'),
///     ],
///     onPicked: (path) => Navigator.of(context).pop(path),
///   ),
/// );
/// ```
class SharedRootsSheet extends StatelessWidget {
  /// Creates the sheet over [items].
  const SharedRootsSheet({
    required this.items,
    required this.onPicked,
    super.key,
  });

  /// The shared items, rendered in the order they are given.
  final List<SharedRootItem> items;

  /// Called with the [SharedRootItem.path] of the entry that was tapped.
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          ListTile(
            key: ValueKey('shared_root_${item.path}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(QuarkIcons.folder_outlined),
            title: Text(item.name, overflow: TextOverflow.ellipsis),
            subtitle: item.owner.isEmpty
                ? null
                : Text(
                    'Shared by ${item.owner}',
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => onPicked(item.path),
          ),
      ],
    );
  }
}
