import 'package:flutter/widgets.dart';

/// The measurements of the Files grid, shared by the flat grid and each
/// per-device group (#1870): the tile's slots, and how many columns of tiles
/// fit a screen width.
abstract final class FileGridLayout {
  /// The padding around a grid, on every side.
  static const padding = 8.0;

  /// The padding inside a tile, around its preview and footer.
  static const cardPadding = 8.0;

  /// The gap between a tile's preview, name and menu row.
  static const slotGap = 8.0;

  /// The height of the line holding a tile's name.
  static const nameSlotHeight = 24.0;

  /// The height of a tile's size and menu row. PopupMenuButton's tap target
  /// is 48 on mobile; a shorter row overflows the tile.
  static const menuRowHeight = 48.0;

  static const _crossAxisSpacing = 8.0;
  static const _minTileWidth = 180.0;

  /// The grid delegate for a screen [width] across: as many columns as fit
  /// tiles at least 180 wide, each tall enough to keep its preview square.
  static SliverGridDelegate delegateFor(double width) {
    final usableWidth = width - padding * 2;
    final calculatedCount =
        ((usableWidth + _crossAxisSpacing) /
                (_minTileWidth + _crossAxisSpacing))
            .floor();
    final crossAxisCount = calculatedCount < 1 ? 1 : calculatedCount;
    // The preview is a square of the tile width minus the padding on each
    // side. The card's margin is uniform, so it shortens the width and the
    // height by the same amount and must not be subtracted again. A fixed
    // aspect ratio left this slot wide and short, and BoxFit.cover cropped
    // the thumbnail to a strip (#2347).
    final tileWidth =
        (usableWidth - _crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final previewExtent = tileWidth - cardPadding * 2;
    const footerExtent = slotGap + nameSlotHeight + slotGap + menuRowHeight;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisExtent: cardPadding * 2 + previewExtent + footerExtent,
      crossAxisSpacing: _crossAxisSpacing,
      mainAxisSpacing: 8,
    );
  }
}
