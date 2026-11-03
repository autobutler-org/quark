import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_device_tags.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_layout.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_node_display.dart';

/// One file or folder in the Files grid: a square preview, the name, and a
/// row with the size, the device tags and the menu. A long press or a
/// right-click opens [menu] at the pointer (#2276), and in selection mode a
/// check mark shows whether the item is selected.
class FileGridTile extends StatelessWidget {
  const FileGridTile({
    required this.item,
    required this.menu,
    required this.isSelected,
    required this.selectionMode,
    required this.showFileSizeAndMenu,
    this.onTap,
    super.key,
  });

  /// The file or folder the tile shows.
  final FileNode item;

  /// The menu the tile's button, long press and right-click open.
  final FileMenu menu;

  /// Whether the item is selected; the tile is tinted when it is.
  final bool isSelected;

  /// Whether the grid is selecting: the check mark shows and the menu does
  /// not open on a long press or right-click.
  final bool selectionMode;

  /// Whether the size and the menu show. The folder picker leaves both off.
  final bool showFileSizeAndMenu;

  /// Called when the tile is tapped; null leaves it inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final menuOpens = showFileSizeAndMenu && !selectionMode;
    return Card(
      clipBehavior: Clip.hardEdge,
      color: isSelected
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : null,
      // InkWell.onLongPress hands over no position, so the gesture is caught
      // outside it; the tile's context is what the entries dispatch against,
      // since it outlives the menu.
      child: GestureDetector(
        onLongPressStart: menuOpens
            ? (details) => menu.showAt(context, details.globalPosition)
            : null,
        onSecondaryTapUp: menuOpens
            ? (details) => menu.showAt(context, details.globalPosition)
            : null,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(FileGridLayout.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: FileGridPreview(item: item),
                    ),
                    const SizedBox(height: FileGridLayout.slotGap),
                    SizedBox(
                      height: FileGridLayout.nameSlotHeight,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: FileGridLayout.slotGap),
                    SizedBox(
                      height: FileGridLayout.menuRowHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (showFileSizeAndMenu)
                            Flexible(
                              child: Text(
                                formatFileSize(
                                  item.size,
                                  item.isDir,
                                  compressedSize: item.compressedSize,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Flexible(child: FileDeviceTags(item: item)),
                          if (showFileSizeAndMenu) FileMenuButton(menu: menu),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (selectionMode)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IgnorePointer(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
