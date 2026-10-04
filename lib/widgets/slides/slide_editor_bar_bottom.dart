import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's second bar row: which slide is showing on the left,
/// and the canvas zoom on the right — zoom out, the zoom as a percentage of
/// the fitted slide (tapping it fits the slide again), and zoom in.
///
/// Below `QuarkAppBarBottom.collapseBreakpoint` the three collapse into a
/// menu labeled "Zoom", so a phone's top row keeps room for undo, redo and
/// the save state. A pinch on the canvas zooms there too.
///
/// Key prefixes: `slide_zoom_out`, `slide_zoom_fit` and `slide_zoom_in` on
/// the buttons; `app_bar_bottom_menu` on the menu, and `slide_menu_zoom_out`,
/// `slide_menu_zoom_fit` and `slide_menu_zoom_in` on its items.
class SlideEditorBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  /// Creates the row reading [position], at [zoomPercent].
  const SlideEditorBarBottom({
    required this.position,
    required this.zoomPercent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    super.key,
  });

  /// Where the selected slide is, such as "Slide 2 of 5".
  final String position;

  /// The zoom as the chip reads it, such as "125%".
  final String zoomPercent;

  /// Zooms in a step; null at the largest zoom.
  final VoidCallback? onZoomIn;

  /// Zooms out a step; null at the smallest zoom.
  final VoidCallback? onZoomOut;

  /// Fits the whole slide in the canvas.
  final VoidCallback onFit;

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final fitLabel = 'Fit slide ($zoomPercent)';
    return QuarkAppBarBottom(
      lead: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          position,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
        ),
      ),
      actions: [
        QuarkBarIconButton(
          key: const ValueKey('slide_zoom_out'),
          icon: QuarkIcons.zoom_out,
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
        ),
        QuarkBarChip(
          key: const ValueKey('slide_zoom_fit'),
          icon: QuarkIcons.fit_screen,
          label: zoomPercent,
          tooltip: 'Fit slide',
          keepLabel: true,
          onPressed: onFit,
        ),
        QuarkBarIconButton(
          key: const ValueKey('slide_zoom_in'),
          icon: QuarkIcons.zoom_in,
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
        ),
      ],
      menuLabel: 'Zoom',
      menuIcon: QuarkIcons.zoom_in,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('slide_menu_zoom_out'),
          leadingIcon: const Icon(QuarkIcons.zoom_out),
          onPressed: onZoomOut,
          child: const Text('Zoom out'),
        ),
        MenuItemButton(
          key: const ValueKey('slide_menu_zoom_fit'),
          leadingIcon: const Icon(QuarkIcons.fit_screen),
          onPressed: onFit,
          child: Text(fitLabel),
        ),
        MenuItemButton(
          key: const ValueKey('slide_menu_zoom_in'),
          leadingIcon: const Icon(QuarkIcons.zoom_in),
          onPressed: onZoomIn,
          child: const Text('Zoom in'),
        ),
      ],
    );
  }
}
