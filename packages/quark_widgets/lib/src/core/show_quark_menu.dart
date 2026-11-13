import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/quark_menu_entry.dart';
import '../theme/quark_tokens.dart';
import 'quark_loader.dart';
import 'quark_menu_label.dart';

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
  final overlayContext = Overlay.of(context).context;
  final overlay = overlayContext.findRenderObject()! as RenderBox;
  // The stock layout keeps a menu inside the overlay, not above a phone's
  // keyboard, so a menu opened near the keyboard ran under it (#4051). With
  // the keyboard up, a menu that would cross it opens upward from [position]
  // instead, and one taller than the room left scrolls.
  // The overlay's media query: a Scaffold strips the insets from its body's.
  final media = MediaQuery.of(overlayContext);
  final keyboard = media.viewInsets.bottom;
  var top = position.dy;
  BoxConstraints? constraints;
  if (keyboard > 0) {
    const screenPadding = 8.0;
    final floor = overlay.size.height - keyboard - screenPadding;
    // ponytail: assumes the stock 48px rows and 8px menu padding; measure
    // the menu if a theme ever changes them.
    final height = entries.fold<double>(
      2 * screenPadding,
      (sum, e) => sum + (e.isDivider ? 1 : kMinInteractiveDimension),
    );
    if (top + height > floor) {
      top = math.max(media.padding.top + screenPadding, top - height);
    }
    // The stock menu's width limits, which `constraints` replaces.
    constraints = BoxConstraints(
      minWidth: 112,
      maxWidth: 280,
      maxHeight: floor - top,
    );
  }
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      Offset(position.dx, top) & Size.zero,
      Offset.zero & overlay.size,
    ),
    constraints: constraints,
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
                  const SizedBox(
                    width: quarkMenuIconSize,
                    height: quarkMenuIconSize,
                    child: Center(child: QuarkLoader(size: quarkMenuIconSize)),
                  )
                else if (entry.icon != null)
                  SizedBox(
                    width: quarkMenuIconSize,
                    height: quarkMenuIconSize,
                    child: Icon(
                      entry.icon,
                      size: quarkMenuIconSize,
                      color: entry.destructive ? tokens.error : null,
                    ),
                  ),
                if (entry.busy || entry.icon != null)
                  const SizedBox(width: quarkMenuIconGap),
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
