import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/slide_document_controller.dart';
import '../controller/slide_document_notifier.dart';
import '../geometry/frame_geometry.dart';
import '../geometry/slide_handle.dart';
import '../geometry/slide_snapping.dart';
import '../geometry/slide_viewport.dart';
import '../model/element_frame.dart';
import '../model/presentation.dart';
import '../model/slide.dart';
import '../model/slide_element.dart';
import '../model/slide_size.dart';
import 'slide_canvas_style.dart';
import 'slide_element_label.dart';
import 'slide_image_source.dart';
import 'slide_selection_overlay.dart';
import 'slide_stage.dart';

/// Shows one slide scaled to fit its box, with letterbox bars, at the presentation's
/// aspect ratio, and — unless built [SlideCanvas.readOnly] — edits it.
///
/// **Editing.** The default constructor edits the slide [slideId] of
/// [document]. Every change goes through the document's
/// [SlideDocumentController], and each gesture is one undo step:
///
/// - tap or click an element to select it; Shift, Ctrl or Cmd adds or
///   removes it instead; drag on empty slide to select by marquee;
/// - drag a selection to move it, snapping its edges and center to the
///   slide's and to other elements' (hold Alt to place freely), with guide
///   lines while it snaps;
/// - drag one of a single selection's eight handles to resize (Shift keeps
///   the aspect ratio at a corner), or its rotate handle to rotate (Shift
///   steps by 15°);
/// - the arrow keys nudge by one slide unit, ten with Shift; Delete or
///   Backspace deletes; Escape deselects; Tab and Shift+Tab select the
///   next and previous element in stacking order and then let focus move
///   on; Ctrl or Cmd with `]` or `[` brings forward or sends backward, and
///   with Shift as well, to the front or back;
/// - scroll to pan a zoomed slide, Ctrl or Cmd scroll (or pinch) to zoom
///   about the pointer, middle-drag or two fingers to pan.
///
/// The caller owns [selection] and [zoom] and hears about changes through
/// [onSelectionChanged] and [onZoomChanged]; zoom is relative to fitting
/// the box, from [minZoom] to [maxZoom]. Handles are drawn
/// [SlideCanvasStyle.handleSize] across but grab within
/// [SlideCanvasStyle.handleHitSize]. The canvas draws without animation, so
/// there is no motion for reduced-motion settings to remove.
///
/// **Read-only.** [SlideCanvas.readOnly] draws a [Slide] with no chrome and
/// no input, for thumbnails and presenting.
///
/// Images are drawn by [imageBuilder]; the package never loads one. The
/// canvas needs a bounded box when editing and handles pointers itself, so
/// do not put it in a scroll view. Keys: each element is
/// `slide_element_<id>` and each handle `slide_handle_<id>` (see
/// [SlideHandle.keyName]).
///
/// ```dart
/// ListenableBuilder(
///   listenable: selection,
///   builder: (context, _) => SlideCanvas(
///     document: doc,
///     slideId: slideId,
///     selection: selection.value,
///     onSelectionChanged: (ids) => selection.value = ids,
///     imageBuilder: (context, image) =>
///         Image.network(image.source, fit: image.fit),
///   ),
/// );
/// ```
class SlideCanvas extends StatefulWidget {
  /// Creates an editing canvas for the slide [slideId] of [document].
  const SlideCanvas({
    super.key,
    required SlideDocumentNotifier this.document,
    required String this.slideId,
    this.selection = const {},
    this.onSelectionChanged,
    this.zoom = 1,
    this.onZoomChanged,
    this.imageBuilder,
    this.style,
    this.elementLabel = defaultSlideElementLabel,
    this.padding = const EdgeInsets.all(24),
    this.focusNode,
    this.autofocus = false,
  })  : slide = null,
        size = null;

  /// Creates a canvas that only draws [slide], at [size], for a thumbnail or
  /// a presentation. It sizes itself to [size]'s aspect ratio within its
  /// constraints.
  const SlideCanvas.readOnly({
    super.key,
    required Slide this.slide,
    required SlideSize this.size,
    this.imageBuilder,
    this.style,
    this.elementLabel = defaultSlideElementLabel,
    this.padding = EdgeInsets.zero,
  })  : document = null,
        slideId = null,
        selection = const {},
        onSelectionChanged = null,
        zoom = 1,
        onZoomChanged = null,
        focusNode = null,
        autofocus = false;

  /// The smallest zoom, half the fitted size.
  static const minZoom = 0.5;

  /// The largest zoom, twice the fitted size.
  static const maxZoom = 2.0;

  /// The document being edited, or `null` when read-only.
  final SlideDocumentNotifier? document;

  /// The id of the slide being edited, or `null` when read-only.
  final String? slideId;

  /// The slide drawn when read-only.
  final Slide? slide;

  /// The slide size when read-only.
  final SlideSize? size;

  /// The ids of the selected elements. Ids not on the slide are ignored.
  final Set<String> selection;

  /// Called with the new selection whenever a gesture or key changes it.
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// The zoom, relative to fitting the box: 1 fits, 0.5 is half that.
  final double zoom;

  /// Called with a new zoom, within [minZoom] and [maxZoom], on a pinch or
  /// a Ctrl-scroll. Without it the zoom stays put.
  final ValueChanged<double>? onZoomChanged;

  /// Draws image elements and background images.
  final SlideImageBuilder? imageBuilder;

  /// Chrome colors and sizes; defaults to [SlideCanvasStyle.fromTheme].
  final SlideCanvasStyle? style;

  /// Names elements for a screen reader.
  final SlideElementLabel elementLabel;

  /// Space around the slide at zoom 1, where handles on its edge still fit.
  final EdgeInsets padding;

  /// The focus node keyboard commands arrive on; the canvas makes its own
  /// when none is given.
  final FocusNode? focusNode;

  /// Whether to take focus when first built.
  final bool autofocus;

  /// Whether the canvas only draws.
  bool get readOnly => document == null;

  @override
  State<SlideCanvas> createState() => _SlideCanvasState();
}

enum _GestureKind {
  move(edits: true),
  resize(edits: true),
  rotate(edits: true),
  marquee(edits: false),
  pan(edits: false);

  const _GestureKind({required this.edits});

  final bool edits;
}

/// One pointer's drag, from pointer down to up.
class _Gesture {
  _Gesture(
    this.kind, {
    required this.pointer,
    required this.startView,
    required this.startSlide,
    this.ids = const {},
    this.handle,
    this.frame,
    this.isLine = false,
    this.startBounds,
    this.collapseTo,
    this.startPan = Offset.zero,
  });

  final _GestureKind kind;
  final int pointer;
  final Offset startView;
  final Offset startSlide;

  /// The elements a move drags, or the one a resize or rotate changes; for
  /// a marquee, the selection it adds to.
  final Set<String> ids;
  final SlideHandle? handle;
  final ElementFrame? frame;
  final bool isLine;
  final Rect? startBounds;

  /// The element to select alone if this ends as a tap on a multi-selection.
  final String? collapseTo;
  final Offset startPan;

  bool started = false;
  Offset applied = Offset.zero;

  /// The controller holding this gesture's open batch, if it opened one.
  SlideDocumentController? batch;
  Presentation? before;
}

/// Two fingers down: the slide point under their midpoint follows it, and
/// the zoom follows their spread.
class _Pinch {
  _Pinch(this.slidePoint, this.distance, this.zoom);

  final Offset slidePoint;
  final double distance;
  final double zoom;
}

class _SlideCanvasState extends State<SlideCanvas> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'SlideCanvas'));

  late Set<String> _selection = widget.selection;
  Offset _pan = Offset.zero;
  SlideViewport? _viewport;
  final Map<int, Offset> _pointers = {};
  _Gesture? _gesture;
  _Pinch? _pinch;
  double _trackpadZoom = 1;
  List<SnapGuide> _guides = const [];
  Rect? _marquee;
  MouseCursor _cursor = MouseCursor.defer;

  SlideDocumentController get _doc => widget.document!.controller;

  Slide? get _slide => widget.document!.presentation.slideById(widget.slideId!);

  SlideSize get _size => widget.document!.presentation.size;

  SlideCanvasStyle get _style =>
      widget.style ?? SlideCanvasStyle.fromTheme(Theme.of(context));

  @override
  void didUpdateWidget(SlideCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(widget.selection, oldWidget.selection)) {
      _selection = widget.selection;
    }
    if (widget.slideId != oldWidget.slideId ||
        widget.document != oldWidget.document) {
      _cancelGesture();
      _selection = widget.selection;
    }
  }

  @override
  void dispose() {
    _cancelGesture();
    _ownFocusNode?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// The selected ids that are on [slide], back to front.
  Set<String> _validSelection(Slide slide) => {
        for (final e in slide.elements)
          if (_selection.contains(e.id)) e.id,
      };

  void _select(Set<String> ids) {
    if (setEquals(ids, _selection)) return;
    setState(() => _selection = ids);
    widget.onSelectionChanged?.call(ids);
  }

  // ---------------------------------------------------------------------------
  // Pointer gestures
  // ---------------------------------------------------------------------------

  bool get _additive {
    final keys = HardwareKeyboard.instance;
    return keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed;
  }

  void _onPointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    final mouse = event.kind == PointerDeviceKind.mouse;
    if (mouse && event.buttons == kMiddleMouseButton) {
      setState(_cancelGesture);
      _gesture = _Gesture(
        _GestureKind.pan,
        pointer: event.pointer,
        startView: event.localPosition,
        startSlide: Offset.zero,
        startPan: _viewport?.pan ?? Offset.zero,
      );
      return;
    }
    if (mouse && event.buttons != kPrimaryMouseButton) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      setState(() => _cancelGesture(revert: true));
      _startPinch();
    } else if (_pointers.length == 1 && _pinch == null) {
      _gesture = _startGesture(event);
    }
  }

  _Gesture? _startGesture(PointerDownEvent event) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return null;
    final point = event.localPosition;
    final slidePoint = viewport.toSlide(point);
    final selected = _validSelection(slide);
    _Gesture gesture(
      _GestureKind kind,
      Set<String> ids, {
      SlideHandle? handle,
      SlideElement? element,
      String? collapseTo,
    }) =>
        _Gesture(
          kind,
          pointer: event.pointer,
          startView: point,
          startSlide: slidePoint,
          ids: ids,
          handle: handle,
          frame: element?.frame,
          isLine: element is LineElement,
          startBounds: kind == _GestureKind.move ? slide.boundsOf(ids) : null,
          collapseTo: collapseTo,
        );

    if (selected.length == 1) {
      final element = slide.elementById(selected.single)!;
      final handle = _handleAt(element.frame, point, viewport);
      if (handle != null) {
        return gesture(
          handle.isResize ? _GestureKind.resize : _GestureKind.rotate,
          selected,
          handle: handle,
          element: element,
        );
      }
    }
    final hit = slide
        .elementAt(slidePoint, tolerance: _style.handleSize / viewport.scale)
        ?.id;
    if (hit == null) {
      if (!_additive) _select(const {});
      return gesture(_GestureKind.marquee, _additive ? selected : const {});
    }
    if (_additive) {
      final next = {...selected};
      if (!next.remove(hit)) next.add(hit);
      _select(next);
      return next.contains(hit) ? gesture(_GestureKind.move, next) : null;
    }
    if (!selected.contains(hit)) {
      _select({hit});
      return gesture(_GestureKind.move, {hit});
    }
    return gesture(
      _GestureKind.move,
      selected,
      collapseTo: selected.length > 1 ? hit : null,
    );
  }

  /// The handle of a single selected [frame] whose hit box holds the
  /// viewport point [point], nearest first.
  SlideHandle? _handleAt(
    ElementFrame frame,
    Offset point,
    SlideViewport viewport,
  ) {
    final reach = _style.handleHitSize / 2;
    SlideHandle? best;
    var bestDistance = double.infinity;
    for (final handle in SlideHandle.values) {
      final center = viewport.toView(
        frame.handlePoint(
          handle,
          rotateOffset: _style.rotateHandleOffset / viewport.scale,
        ),
      );
      final offset = point - center;
      if (offset.dx.abs() > reach || offset.dy.abs() > reach) continue;
      if (offset.distance < bestDistance) {
        best = handle;
        bestDistance = offset.distance;
      }
    }
    return best;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      _pointers[event.pointer] = event.localPosition;
    }
    if (_pinch != null) return _updatePinch();
    final gesture = _gesture;
    if (gesture == null || gesture.pointer != event.pointer) return;
    if (!gesture.started) {
      final travel = (event.localPosition - gesture.startView).distance;
      if (travel < computeHitSlop(event.kind, null)) return;
      gesture.started = true;
      if (gesture.kind.edits) {
        gesture
          ..batch = _doc
          ..before = _doc.presentation;
        _doc.beginBatch();
      }
    }
    _updateGesture(gesture, event.localPosition);
  }

  void _updateGesture(_Gesture gesture, Offset point) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return;
    final slideId = widget.slideId!;
    final slidePoint = viewport.toSlide(point);
    final travel = slidePoint - gesture.startSlide;
    final keys = HardwareKeyboard.instance;
    switch (gesture.kind) {
      case _GestureKind.move:
        final ids = gesture.ids.where((id) => slide.elementById(id) != null);
        final snap = keys.isAltPressed || gesture.startBounds == null
            ? SnapResult(travel, const [])
            : snapMove(
                moving: gesture.startBounds!,
                delta: travel,
                slide: slide,
                size: _size,
                exclude: gesture.ids,
                threshold: _style.snapDistance / viewport.scale,
              );
        final step = snap.delta - gesture.applied;
        if (step != Offset.zero) {
          _doc.moveElements(slideId, ids, step.dx, step.dy);
        }
        gesture.applied = snap.delta;
        setState(() => _guides = snap.guides);
      case _GestureKind.resize:
        final frame = gesture.frame!.resized(
          gesture.handle!,
          travel,
          keepAspect: keys.isShiftPressed,
          minExtent: gesture.isLine ? 0 : 1,
        );
        _doc.resizeElement(
          slideId,
          gesture.ids.single,
          width: frame.width,
          height: frame.height,
          x: frame.x,
          y: frame.y,
        );
      case _GestureKind.rotate:
        _doc.rotateElement(
          slideId,
          gesture.ids.single,
          gesture.frame!.rotationToward(slidePoint, snap: keys.isShiftPressed),
        );
      case _GestureKind.marquee:
        final area = Rect.fromPoints(gesture.startSlide, slidePoint);
        _select({...gesture.ids, ...slide.elementsInside(area)});
        setState(() => _marquee = area);
      case _GestureKind.pan:
        _viewTo(gesture.startPan + (point - gesture.startView), widget.zoom);
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinch != null) {
      if (_pointers.length < 2) _pinch = null;
      return;
    }
    final gesture = _gesture;
    if (gesture == null || gesture.pointer != event.pointer) return;
    if (!gesture.started && gesture.collapseTo != null) {
      _select({gesture.collapseTo!});
    }
    setState(_cancelGesture);
  }

  /// Ends the current gesture, closing its undo step and clearing its
  /// guides; [revert] undoes what it changed instead, as a second finger
  /// turning a drag into a pinch does. The caller rebuilds.
  void _cancelGesture({bool revert = false}) {
    final gesture = _gesture;
    _gesture = null;
    _guides = const [];
    _marquee = null;
    final batch = gesture?.batch;
    if (batch == null) return;
    batch.endBatch();
    if (revert && batch.presentation != gesture!.before) batch.undo();
  }

  // ---------------------------------------------------------------------------
  // Pan and zoom
  // ---------------------------------------------------------------------------

  /// Pans to [pan] (clamped) at [zoom], reporting a zoom change.
  void _viewTo(Offset pan, double zoom) {
    final viewport = _viewport;
    if (viewport == null) return;
    final clamped = SlideViewport(
      viewportSize: viewport.viewportSize,
      slideSize: viewport.slideSize,
      zoom: zoom,
      pan: pan,
      padding: viewport.padding,
    ).pan;
    if (clamped != _pan) setState(() => _pan = clamped);
    if (zoom != widget.zoom) widget.onZoomChanged?.call(zoom);
  }

  /// [zoom] clamped to the allowed range, or the current zoom when the
  /// caller does not take zoom changes.
  double _allowedZoom(double zoom) => widget.onZoomChanged == null
      ? widget.zoom
      : zoom.clamp(SlideCanvas.minZoom, SlideCanvas.maxZoom);

  void _zoomAround(Offset focal, double zoom) {
    final viewport = _viewport;
    zoom = _allowedZoom(zoom);
    if (viewport == null || zoom == widget.zoom) return;
    _viewTo(viewport.panForZoom(zoom, focal), zoom);
  }

  void _startPinch() {
    final viewport = _viewport;
    if (viewport == null) return;
    final [a, b] = _pointers.values.take(2).toList();
    _pinch = _Pinch(
      viewport.toSlide((a + b) / 2),
      math.max(1, (a - b).distance),
      widget.zoom,
    );
  }

  void _updatePinch() {
    final pinch = _pinch!;
    final viewport = _viewport;
    if (viewport == null || _pointers.length < 2) return;
    final [a, b] = _pointers.values.take(2).toList();
    final zoom = _allowedZoom(pinch.zoom * (a - b).distance / pinch.distance);
    _viewTo(viewport.panToPlace(pinch.slidePoint, (a + b) / 2, zoom), zoom);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final keys = HardwareKeyboard.instance;
      if (event is PointerScaleEvent) {
        _zoomAround(event.localPosition, widget.zoom * event.scale);
      } else if (event is PointerScrollEvent) {
        if (keys.isControlPressed || keys.isMetaPressed) {
          final factor = math.exp(-event.scrollDelta.dy / 200);
          _zoomAround(event.localPosition, widget.zoom * factor);
          return;
        }
        var delta = event.scrollDelta;
        if (keys.isShiftPressed && delta.dx == 0) delta = Offset(delta.dy, 0);
        _viewTo(_pan - delta, widget.zoom);
      }
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) =>
      _trackpadZoom = widget.zoom;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final viewport = _viewport;
    if (viewport == null) return;
    final zoom = _allowedZoom(_trackpadZoom * event.scale);
    final pan = zoom == widget.zoom
        ? _pan
        : viewport.panForZoom(zoom, event.localPosition);
    _viewTo(pan + event.panDelta, zoom);
  }

  void _onHover(PointerHoverEvent event) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return;
    final over = slide.elementAt(
      viewport.toSlide(event.localPosition),
      tolerance: _style.handleSize / viewport.scale,
    );
    final cursor = over == null ? MouseCursor.defer : SystemMouseCursors.move;
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  static final _nudges = {
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
  };

  static final _forwardKeys = {
    LogicalKeyboardKey.bracketRight,
    LogicalKeyboardKey.braceRight,
  };

  static final _backwardKeys = {
    LogicalKeyboardKey.bracketLeft,
    LogicalKeyboardKey.braceLeft,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final slide = _slide;
    if (slide == null || event is KeyUpEvent || _gesture != null) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final selected = _validSelection(slide);
    final slideId = widget.slideId!;
    if (key == LogicalKeyboardKey.tab) {
      return _cycle(slide, selected, backward: keys.isShiftPressed);
    }
    if (selected.isEmpty) return KeyEventResult.ignored;
    final nudge = _nudges[key];
    final command = keys.isControlPressed || keys.isMetaPressed;
    final toFront = _forwardKeys.contains(key);
    if (nudge != null) {
      final step = nudge * (keys.isShiftPressed ? 10 : 1);
      _doc.moveElements(slideId, selected, step.dx, step.dy);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _doc.deleteElements(slideId, selected);
      _select(const {});
    } else if (key == LogicalKeyboardKey.escape) {
      _select(const {});
    } else if (command && (toFront || _backwardKeys.contains(key))) {
      final all = keys.isShiftPressed;
      _doc.arrangeElements(
        slideId,
        selected,
        toFront
            ? (all ? ZOrderMove.toFront : ZOrderMove.forward)
            : (all ? ZOrderMove.toBack : ZOrderMove.backward),
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Selects the element after (or before) the selection in stacking
  /// order. Past either end it deselects and lets focus leave the canvas.
  KeyEventResult _cycle(
    Slide slide,
    Set<String> selected, {
    required bool backward,
  }) {
    final ids = [for (final e in slide.elements) e.id];
    if (ids.isEmpty) return KeyEventResult.ignored;
    final int next;
    if (selected.isEmpty) {
      next = backward ? ids.length - 1 : 0;
    } else {
      next = backward
          ? ids.indexOf(selected.first) - 1
          : ids.indexOf(selected.last) + 1;
    }
    if (next < 0 || next >= ids.length) {
      _select(const {});
      return KeyEventResult.ignored;
    }
    _select({ids[next]});
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (widget.readOnly) {
      final size = widget.size!;
      return Padding(
        padding: widget.padding,
        child: Center(
          child: AspectRatio(
            aspectRatio: size.aspectRatio,
            child: FittedBox(
              child: SlideStage(
                slide: widget.slide!,
                size: size,
                style: style,
                elementLabel: widget.elementLabel,
                imageBuilder: widget.imageBuilder,
              ),
            ),
          ),
        ),
      );
    }
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: widget.document!,
        builder: (context, _) {
          final slide = _slide;
          if (slide == null) return const SizedBox.expand();
          return LayoutBuilder(
            builder: (context, constraints) {
              assert(
                constraints.hasBoundedWidth && constraints.hasBoundedHeight,
                'an editing SlideCanvas needs a bounded box',
              );
              final viewport = _viewport = SlideViewport(
                viewportSize: constraints.biggest,
                slideSize: _size,
                zoom: widget.zoom,
                pan: _pan,
                padding: widget.padding,
              );
              final selected = _validSelection(slide);
              return MouseRegion(
                cursor: _cursor,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  onPointerHover: _onHover,
                  onPointerSignal: _onPointerSignal,
                  onPointerPanZoomStart: _onPanZoomStart,
                  onPointerPanZoomUpdate: _onPanZoomUpdate,
                  child: ClipRect(
                    child: ColoredBox(
                      color: style.backdropColor,
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: viewport.slideRect,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: SlideStage(
                                slide: slide,
                                size: _size,
                                style: style,
                                elementLabel: widget.elementLabel,
                                imageBuilder: widget.imageBuilder,
                                selection: selected,
                                onSelect: (id) {
                                  _focusNode.requestFocus();
                                  _select({id});
                                },
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: SlideSelectionOverlay(
                              viewport: viewport,
                              frames: [
                                for (final e in slide.elements)
                                  if (selected.contains(e.id)) e.frame,
                              ],
                              style: style,
                              guides: _guides,
                              marquee: _marquee,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
