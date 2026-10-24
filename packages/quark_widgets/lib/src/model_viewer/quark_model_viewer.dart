import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'quark_model_camera.dart';
import 'quark_model_mesh.dart';
import 'quark_model_viewer/model_renderer.dart';
import 'quark_model_viewer/model_viewer_controls.dart';
import 'quark_model_viewer/model_viewer_painter.dart';
import 'quark_model_viewer/model_viewer_stats.dart';

/// An interactive 3D view of a triangle mesh: orbit, pan and zoom, a
/// wireframe toggle, reset view, and the model's size and counts.
///
/// Controls:
/// - **Touch:** one finger turns the model, two fingers move it, pinch
///   zooms, double-tap resets.
/// - **Mouse and trackpad:** drag turns, right- or middle-drag (or
///   Shift-drag) moves, the wheel or a pinch zooms.
/// - **Keyboard,** once the canvas has focus: arrows turn, Shift+arrows
///   move, `+` and `-` zoom, `0` or Home resets, `W` toggles wireframe.
///
/// The camera is view state, like a scroll offset, so the viewer keeps it
/// and resets it when [mesh] changes. Whether the model shows as a
/// wireframe is the caller's: [wireframe] in, [onWireframeChanged] out.
/// Nothing moves on its own, so there is no motion to reduce.
///
/// States: a loader while [isLoading]; [error] with a Retry button; "Nothing
/// to show" when [mesh] is null or has no triangles; otherwise the model.
/// The viewer fills the space it is given, so give it a bounded height.
///
/// Key prefixes: `model_viewer_canvas`, `model_viewer_retry`, plus those of
/// `ModelViewerControls` (`model_viewer_wireframe_toggle`,
/// `model_viewer_zoom_in`, `model_viewer_zoom_out`, `model_viewer_reset`)
/// and `ModelViewerStats` (`model_viewer_size`, `model_viewer_triangles`,
/// `model_viewer_vertices`, `model_viewer_hint`, `model_viewer_status`).
///
/// ```dart
/// QuarkModelViewer(
///   mesh: controller.mesh,
///   isLoading: controller.isLoading,
///   error: errorText,
///   onRetry: controller.load,
///   wireframe: controller.wireframe,
///   onWireframeChanged: controller.setWireframe,
/// );
/// ```
class QuarkModelViewer extends StatefulWidget {
  /// Creates a viewer for [mesh].
  const QuarkModelViewer({
    required this.mesh,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.wireframe = false,
    this.onWireframeChanged,
    this.statusLabel,
    super.key,
  });

  /// The model; `parseQuarkModel` makes one from a file's bytes. Null shows
  /// the empty state.
  ///
  /// A mesh with a `QuarkModelMesh.preview` draws the preview while it is
  /// turned, moved or zoomed by a drag, a pinch, the wheel or a held arrow
  /// key, and the full mesh again once the gesture ends or the input has
  /// rested for [settleDelay] (#3231), so a model too detailed to redraw
  /// every frame still moves smoothly.
  final QuarkModelMesh? mesh;

  /// Whether the model is still loading, which shows a loader.
  final bool isLoading;

  /// Why the model could not be shown, rendered as given with a Retry
  /// button; null when it loaded. The caller composes the sentence.
  final String? error;

  /// Called by Retry under [error]. Null leaves the button out.
  final VoidCallback? onRetry;

  /// Whether the model shows as edges rather than shaded faces.
  final bool wireframe;

  /// Called with the opposite of [wireframe] by its button and the `W` key.
  /// Null disables both.
  final ValueChanged<bool>? onWireframeChanged;

  /// A line about the file, shown with the counts; null shows nothing.
  final String? statusLabel;

  /// How far one arrow key press turns the model, in radians.
  static const double keyTurn = math.pi / 12;

  /// How far one Shift+arrow press moves the model, in model radii.
  static const double keyPan = 0.1;

  /// How much one zoom button or key press zooms.
  static const double zoomStep = 1.25;

  /// How long the wheel or a held arrow key must rest before a model with
  /// a preview is drawn in full again.
  static const Duration settleDelay = Duration(milliseconds: 250);

  @override
  State<QuarkModelViewer> createState() => _QuarkModelViewerState();
}

class _QuarkModelViewerState extends State<QuarkModelViewer> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'QuarkModelViewer');
  QuarkModelCamera _camera = QuarkModelCamera.initial;
  ModelRenderer? _renderer;
  ModelRenderer? _previewRenderer;
  bool _focused = false;
  bool _moving = false;
  Timer? _settle;

  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  int _buttons = kPrimaryButton;

  ModelRenderer? get _rendererForMesh {
    final mesh = widget.mesh;
    if (mesh == null || mesh.isEmpty) return null;
    final renderer = _renderer;
    if (renderer != null && identical(renderer.mesh, mesh)) return renderer;
    return _renderer = ModelRenderer(mesh);
  }

  /// The renderer for the mesh's preview, null when it has none to draw.
  ModelRenderer? get _rendererForPreview {
    final preview = widget.mesh?.preview;
    if (preview == null || preview.isEmpty) return null;
    final renderer = _previewRenderer;
    if (renderer != null && identical(renderer.mesh, preview)) {
      return renderer;
    }
    return _previewRenderer = ModelRenderer(preview);
  }

  /// Draws the preview until the gesture ends, or with [settle], until
  /// input has rested for `settleDelay`.
  void _startMoving({bool settle = false}) {
    if (_rendererForPreview == null) return;
    _settle?.cancel();
    if (!_moving) setState(() => _moving = true);
    if (settle) _settle = Timer(QuarkModelViewer.settleDelay, _stopMoving);
  }

  void _stopMoving() {
    _settle?.cancel();
    _settle = null;
    if (_moving && mounted) setState(() => _moving = false);
  }

  @override
  void didUpdateWidget(QuarkModelViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mesh, widget.mesh)) {
      _camera = QuarkModelCamera.initial;
      _settle?.cancel();
      _moving = false;
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _setCamera(QuarkModelCamera camera) {
    if (camera != _camera) setState(() => _camera = camera);
  }

  void _reset() => _setCamera(QuarkModelCamera.initial);

  void _zoom(double factor) => _setCamera(_camera.zoomBy(factor));

  /// Screen pixels to model radii at the current zoom, so a pan keeps the
  /// model under the finger near the center of the view.
  double _panScale(Size size) =>
      2 *
      math.tan(ModelRenderer.fieldOfView / 2) /
      math.sin(ModelRenderer.fieldOfView / 2) /
      size.shortestSide /
      _camera.zoom;

  void _drag(Offset delta, Size size, {required bool pan}) {
    if (pan) {
      final scale = _panScale(size);
      _setCamera(_camera.pan(delta.dx * scale, -delta.dy * scale));
    } else {
      // A drag across the shorter side turns the model about half a turn.
      final turn = math.pi / math.max(size.shortestSide, 1);
      _setCamera(_camera.orbit(delta.dx * turn, delta.dy * turn));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    const turn = QuarkModelViewer.keyTurn, step = QuarkModelViewer.keyPan;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (direction != null) {
      if (event is KeyRepeatEvent) _startMoving(settle: true);
      _setCamera(
        shift
            ? _camera.pan(direction.dx * step, -direction.dy * step)
            : _camera.orbit(direction.dx * turn, direction.dy * turn),
      );
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    final character = event.character;
    if (key == LogicalKeyboardKey.numpadAdd ||
        character == '+' ||
        character == '=') {
      _zoom(QuarkModelViewer.zoomStep);
    } else if (key == LogicalKeyboardKey.numpadSubtract || character == '-') {
      _zoom(1 / QuarkModelViewer.zoomStep);
    } else if (key == LogicalKeyboardKey.home || character == '0') {
      _reset();
    } else if (key == LogicalKeyboardKey.keyW) {
      final onWireframeChanged = widget.onWireframeChanged;
      if (onWireframeChanged == null) return KeyEventResult.ignored;
      onWireframeChanged(!widget.wireframe);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;
    final onRetry = widget.onRetry;
    final mesh = widget.mesh;
    final renderer = _rendererForMesh;
    final preview = _moving ? _rendererForPreview : null;
    if (widget.isLoading) return const Center(child: QuarkLoader());
    if (error != null) {
      return EmptyStateWidget(
        icon: QuarkIcons.error_outline,
        headline: error,
        action: onRetry == null
            ? null
            : FilledButton(
                key: const ValueKey('model_viewer_retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
      );
    }
    if (mesh == null || renderer == null) {
      return const EmptyStateWidget(
        icon: QuarkIcons.shapes,
        headline: 'Nothing to show',
        subtext: 'This model has no surfaces to draw.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return Semantics(
                      label:
                          '3D model. Arrow keys turn it, Shift and the '
                          'arrows move it, plus and minus zoom.',
                      child: Focus(
                        focusNode: _focusNode,
                        onKeyEvent: _onKey,
                        onFocusChange: (focused) =>
                            setState(() => _focused = focused),
                        child: Listener(
                          onPointerDown: (event) {
                            _buttons = event.buttons;
                            _focusNode.requestFocus();
                          },
                          onPointerSignal: (event) {
                            if (event is! PointerScrollEvent) return;
                            GestureBinding.instance.pointerSignalResolver
                                .register(event, (event) {
                                  _startMoving(settle: true);
                                  _zoom(
                                    math
                                        .pow(
                                          1.002,
                                          -(event as PointerScrollEvent)
                                              .scrollDelta
                                              .dy,
                                        )
                                        .toDouble(),
                                  );
                                });
                          },
                          child: GestureDetector(
                            key: const ValueKey('model_viewer_canvas'),
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _reset,
                            onScaleStart: (details) {
                              _lastFocal = details.localFocalPoint;
                              _lastScale = 1;
                              _startMoving();
                            },
                            onScaleEnd: (_) => _stopMoving(),
                            onScaleUpdate: (details) {
                              final delta =
                                  details.localFocalPoint - _lastFocal;
                              _lastFocal = details.localFocalPoint;
                              // Two fingers, a trackpad, a right or middle
                              // mouse button, or Shift moves; anything else
                              // turns.
                              final pan =
                                  details.pointerCount > 1 ||
                                  _buttons & kPrimaryButton == 0 ||
                                  HardwareKeyboard.instance.isShiftPressed;
                              _drag(delta, size, pan: pan);
                              if (details.scale != _lastScale &&
                                  details.scale > 0) {
                                _zoom(details.scale / _lastScale);
                                _lastScale = details.scale;
                              }
                            },
                            child: DecoratedBox(
                              position: DecorationPosition.foreground,
                              decoration: BoxDecoration(
                                border: _focused
                                    ? Border.all(
                                        color: tokens.primary,
                                        width: tokens.focusRingWidth,
                                      )
                                    : null,
                              ),
                              child: CustomPaint(
                                size: size,
                                painter: ModelViewerPainter(
                                  renderer: preview ?? renderer,
                                  camera: _camera,
                                  color: tokens.primary,
                                  edgeColor: tokens.foreground,
                                  wireframe: widget.wireframe,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: tokens.spacingSm,
                right: tokens.spacingSm,
                child: ModelViewerControls(
                  wireframe: widget.wireframe,
                  onWireframeChanged: widget.onWireframeChanged,
                  onZoomIn: () => _zoom(QuarkModelViewer.zoomStep),
                  onZoomOut: () => _zoom(1 / QuarkModelViewer.zoomStep),
                  onReset: _reset,
                ),
              ),
            ],
          ),
        ),
        ModelViewerStats(mesh: mesh, statusLabel: widget.statusLabel),
      ],
    );
  }
}
