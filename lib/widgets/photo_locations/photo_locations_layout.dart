import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/photo_map_config.dart';

/// How the Locations view arranges its map and the chosen cluster's photos
/// (#3557). Wide, the photos take a pane beside the map, and Escape closes
/// it. Narrow, the map fills the screen and the photos rise in a bottom
/// sheet that drags up to a full-screen grid; Back closes the sheet and
/// leaves the map where it was.
///
/// Keyed `photo_locations_sheet` on the phone's sheet and
/// `photo_locations_pane` on the wide pane.
class PhotoLocationsLayout extends StatelessWidget {
  /// Creates the layout.
  const PhotoLocationsLayout({
    required this.map,
    required this.onClosePane,
    this.pane,
    super.key,
  });

  /// The map, or the list standing in for it.
  final Widget map;

  /// Builds the photos pane with the scroll controller it must use, the
  /// sheet's on a phone. Null while no cluster is chosen.
  final Widget Function(ScrollController? scrollController)? pane;

  /// Closes the pane.
  final VoidCallback onClosePane;

  @override
  Widget build(BuildContext context) {
    final pane = this.pane;
    return PopScope(
      canPop: pane == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClosePane();
      },
      child: CallbackShortcuts(
        bindings: {
          if (pane != null)
            const SingleActivator(LogicalKeyboardKey.escape): onClosePane,
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= PhotoMapConfig.splitBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: map),
                  if (pane != null) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(
                      key: const ValueKey('photo_locations_pane'),
                      width: PhotoMapConfig.paneWidth,
                      child: pane(null),
                    ),
                  ],
                ],
              );
            }
            return Stack(
              children: [
                Positioned.fill(child: map),
                if (pane != null)
                  DraggableScrollableSheet(
                    key: const ValueKey('photo_locations_sheet'),
                    initialChildSize: 0.4,
                    minChildSize: 0.25,
                    snap: true,
                    builder: (context, controller) => ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: pane(controller),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
