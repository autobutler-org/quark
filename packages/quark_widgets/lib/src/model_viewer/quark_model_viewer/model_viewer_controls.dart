import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../layout/quark_bar_icon_button.dart';
import '../../theme/quark_tokens.dart';

/// The buttons floating over a `QuarkModelViewer`'s canvas: wireframe,
/// zoom in, zoom out and reset view, stacked in a card so they read over
/// any model.
///
/// Key prefixes: `model_viewer_wireframe_toggle`, `model_viewer_zoom_in`,
/// `model_viewer_zoom_out` and `model_viewer_reset`.
///
/// ```dart
/// ModelViewerControls(
///   wireframe: false,
///   onWireframeChanged: setWireframe,
///   onZoomIn: zoomIn,
///   onZoomOut: zoomOut,
///   onReset: reset,
/// );
/// ```
class ModelViewerControls extends StatelessWidget {
  /// Creates the controls.
  const ModelViewerControls({
    required this.wireframe,
    required this.onWireframeChanged,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    super.key,
  });

  /// Whether the model shows as edges, shown as the toggle's selected state.
  final bool wireframe;

  /// Called with the opposite of [wireframe] when the toggle is tapped. Null
  /// disables the toggle.
  final ValueChanged<bool>? onWireframeChanged;

  /// Moves the camera closer.
  final VoidCallback onZoomIn;

  /// Moves the camera away.
  final VoidCallback onZoomOut;

  /// Returns the camera to the view the model opened on.
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onWireframeChanged = this.onWireframeChanged;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QuarkBarIconButton(
            key: const ValueKey('model_viewer_wireframe_toggle'),
            icon: QuarkIcons.wireframe,
            tooltip: 'Wireframe',
            selected: wireframe,
            onPressed: onWireframeChanged == null
                ? null
                : () => onWireframeChanged(!wireframe),
          ),
          QuarkBarIconButton(
            key: const ValueKey('model_viewer_zoom_in'),
            icon: QuarkIcons.zoom_in,
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
          ),
          QuarkBarIconButton(
            key: const ValueKey('model_viewer_zoom_out'),
            icon: QuarkIcons.zoom_out,
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
          ),
          QuarkBarIconButton(
            key: const ValueKey('model_viewer_reset'),
            icon: QuarkIcons.fit_screen,
            tooltip: 'Reset view',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}
