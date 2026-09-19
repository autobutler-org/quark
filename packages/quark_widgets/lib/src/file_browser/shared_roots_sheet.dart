import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/shared_root_item.dart';
import '../theme/quark_tokens.dart';

/// A draggable bottom sheet for opening one of the folders somebody else
/// shared with the signed-in account.
///
/// Ad-hoc shares land wherever their owner keeps them, so there is no one
/// folder holding them all. The sheet is that list: each entry names the
/// shared item and who owns it, and tapping one hands its path back through
/// [onPicked]. It never loads — the caller has the [items] already — and a
/// caller with none to show opens no sheet at all. Show it with
/// `showModalBottomSheet(isScrollControlled: true, ...)`.
///
/// Key prefixes: `shared_root_<path>` on each entry.
///
/// ```dart
/// showModalBottomSheet<String>(
///   context: context,
///   isScrollControlled: true,
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
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Column(
        children: [
          SizedBox(height: tokens.spacingSm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline,
              borderRadius: BorderRadius.circular(tokens.radiusSm / 2),
            ),
          ),
          SizedBox(height: tokens.spacingSm + tokens.spacingXs),
          const Text(
            'Shared with me',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: tokens.spacingXs),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                for (final item in items)
                  ListTile(
                    key: ValueKey('shared_root_${item.path}'),
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
            ),
          ),
          SizedBox(height: tokens.spacingSm),
        ],
      ),
    );
  }
}
