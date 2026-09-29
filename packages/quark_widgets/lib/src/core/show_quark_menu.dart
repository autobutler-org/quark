import 'package:flutter/material.dart';

import '../models/quark_menu_entry.dart';
import '../theme/quark_tokens.dart';
import 'quark_loader.dart';

/// Opens an item's menu at [position], a global offset: where the pointer was
/// right-clicked or the finger long-pressed, or under a menu button.
///
/// The one way Quark opens a per-item menu, so the three-dot button, the long
/// press and the right-click on an item all look and behave alike (#2267). The
/// chosen entry's `onSelected` runs after the menu has closed. Does nothing
/// when [entries] holds no row, since an empty menu is a box with nothing to
/// pick.
///
/// ```dart
/// onSecondaryTapUp: (details) => showQuarkMenu(
///   context,
///   position: details.globalPosition,
///   entries: [QuarkMenuEntry(label: 'Rename', onSelected: rename)],
/// ),
/// ```
Future<void> showQuarkMenu(
  BuildContext context, {
  required Offset position,
  required List<QuarkMenuEntry> entries,
}) async {
  if (entries.every((e) => e.isDivider)) return;
  final tokens = QuarkTokens.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      for (final (index, entry) in entries.indexed)
        if (entry.isDivider)
          const PopupMenuDivider(height: 1)
        else
          PopupMenuItem<int>(
            key: entry.key,
            value: index,
            enabled: entry.onSelected != null,
            child: Row(
              children: [
                if (entry.busy)
                  const QuarkLoader(size: 16)
                else if (entry.icon != null)
                  Icon(
                    entry.icon,
                    size: 18,
                    color: entry.destructive ? tokens.error : null,
                  ),
                if (entry.busy || entry.icon != null)
                  SizedBox(width: tokens.spacingSm + tokens.spacingXs),
                Flexible(
                  child: Text(
                    entry.label,
                    overflow: TextOverflow.ellipsis,
                    style: entry.destructive
                        ? TextStyle(color: tokens.error)
                        : null,
                  ),
                ),
              ],
            ),
          ),
    ],
  );
  if (picked == null) return;
  entries[picked].onSelected?.call();
}

/// Where a menu opened from the widget at [context] should start: the bottom
/// left corner of that widget's box, so the menu drops down from a button.
Offset quarkMenuAnchor(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.bottomLeft(Offset.zero));
}
