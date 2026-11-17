import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Follows one pointer across a `PhotoGrid` and reports which tiles a drag
/// covers (#4171). The grid owns one and wraps every tile in a
/// `PhotoGridDragTarget` that hands it pointer downs.
///
/// Two drags select:
///
/// - **A mouse drag** that starts on a tile and moves past the pan slop: a
///   rubber band, the tiles in the rows and columns between the tile it
///   started on and the one under the pointer. Columns count within each
///   section, the way the grid draws them.
/// - **A long press that keeps going**: [longPressed] starts it, and it
///   covers every tile between the two in grid order, so a swipe down a
///   phone takes whole rows. A touch that moves before the long press is
///   the scroll view's, and is never seen here.
///
/// Either way the update carries every index the drag covers now, so a drag
/// that turns back drops what it no longer covers. Held near the top or
/// bottom of the enclosing [Scrollable], the drag scrolls it and keeps
/// selecting. Only loaded tiles can be covered: a pointer over a header, a
/// gap or the loading cell keeps the last tile.
///
/// The grid reconfigures it on every build through [configure].
class PhotoGridDragSelection {
  /// How far from the top or bottom edge of the scroll view a drag starts
  /// scrolling it.
  static const double edge = 56;

  /// The most a held drag scrolls in one tick, at the very edge.
  static const double maxScrollStep = 24;

  /// How often a held drag scrolls.
  static const Duration tick = Duration(milliseconds: 16);

  int _crossAxisCount = 1;
  int _photoCount = 0;
  List<int> _sectionStarts = const [0];
  VoidCallback? _onStart;
  ValueChanged<List<int>>? _onUpdate;
  VoidCallback? _onEnd;
  ScrollableState? _scrollable;
  int _viewId = 0;

  int? _pointer;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _downAt = Offset.zero;
  Offset _lastAt = Offset.zero;
  int _downIndex = 0;
  int? _anchor;
  int? _current;
  bool _rubberBand = false;
  Timer? _scrollTimer;

  /// Whether a drag is selecting right now.
  bool get isDragging => _anchor != null;

  /// Takes the grid's layout and callbacks from its latest build. Without
  /// [onUpdate] nothing is tracked.
  void configure({
    required int crossAxisCount,
    required int photoCount,
    required List<int> sectionStarts,
    required ScrollableState? scrollable,
    required int viewId,
    required VoidCallback? onStart,
    required ValueChanged<List<int>>? onUpdate,
    required VoidCallback? onEnd,
  }) {
    _crossAxisCount = math.max(1, crossAxisCount);
    _photoCount = photoCount;
    _sectionStarts = sectionStarts.isEmpty ? const [0] : sectionStarts;
    _scrollable = scrollable;
    _viewId = viewId;
    _onStart = onStart;
    _onUpdate = onUpdate;
    _onEnd = onEnd;
  }

  /// A pointer went down on the tile at [index]. Follows it until it lifts.
  void pointerDown(int index, PointerDownEvent event) {
    if (_onUpdate == null || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _pointer = event.pointer;
    _kind = event.kind;
    _downAt = event.position;
    _lastAt = event.position;
    _downIndex = index;
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _route);
  }

  /// The tile at [index] reported a long press that starts or toggles
  /// selection. If the pointer that pressed it is still down, the drag that
  /// follows selects.
  void longPressed(int index) {
    if (_pointer == null || isDragging || index != _downIndex) return;
    _start(rubberBand: _kind == PointerDeviceKind.mouse);
  }

  /// Stops following the pointer and scrolling, without reporting an end.
  void dispose() {
    _scrollTimer?.cancel();
    final pointer = _pointer;
    if (pointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, _route);
    }
    _pointer = null;
  }

  void _route(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _lastAt = event.position;
      if (!isDragging) {
        final slop = computePanSlop(_kind, null);
        if (_kind != PointerDeviceKind.mouse ||
            (event.position - _downAt).distance <= slop) {
          return;
        }
        _start(rubberBand: true);
      }
      _cover();
      _scrollIfAtEdge();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      final wasDragging = isDragging;
      dispose();
      _anchor = null;
      _current = null;
      if (wasDragging) _onEnd?.call();
    }
  }

  void _start({required bool rubberBand}) {
    _rubberBand = rubberBand;
    _anchor = _downIndex;
    _current = null;
    _onStart?.call();
  }

  /// Finds the tile under the pointer and, when it changed, reports what
  /// the drag covers.
  void _cover() {
    final anchor = _anchor;
    if (anchor == null) return;
    final index = _tileAt(_lastAt) ?? _current ?? anchor;
    if (index == _current) return;
    _current = index;
    _onUpdate?.call(
      _rubberBand ? _rectangle(anchor, index) : _run(anchor, index),
    );
  }

  int? _tileAt(Offset position) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, position, _viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final data = target.metaData;
        if (data is PhotoGridDragTag &&
            identical(data.owner, this) &&
            data.index < _photoCount) {
          return data.index;
        }
      }
    }
    return null;
  }

  List<int> _run(int a, int b) => [
    for (var i = math.min(a, b); i <= math.max(a, b); i++) i,
  ];

  List<int> _rectangle(int a, int b) {
    final first = math.min(a, b);
    final last = math.max(a, b);
    final firstStart = _sectionStartOf(first);
    final lastStart = _sectionStartOf(last);
    final rowStart =
        firstStart + (first - firstStart) ~/ _crossAxisCount * _crossAxisCount;
    final lastSectionEnd = _sectionEndOf(last);
    final rowEnd = math.min(
      lastStart + ((last - lastStart) ~/ _crossAxisCount + 1) * _crossAxisCount,
      lastSectionEnd,
    );
    final colA = _columnOf(a);
    final colB = _columnOf(b);
    final minCol = math.min(colA, colB);
    final maxCol = math.max(colA, colB);
    return [
      for (var i = rowStart; i < rowEnd; i++)
        if (_columnOf(i) >= minCol && _columnOf(i) <= maxCol) i,
    ];
  }

  int _columnOf(int index) =>
      (index - _sectionStartOf(index)) % _crossAxisCount;

  int _sectionStartOf(int index) {
    var start = 0;
    for (final s in _sectionStarts) {
      if (s > index) break;
      start = s;
    }
    return start;
  }

  int _sectionEndOf(int index) {
    for (final s in _sectionStarts) {
      if (s > index) return s;
    }
    return _photoCount;
  }

  /// Scrolls the enclosing scroll view while the pointer is held within
  /// [edge] of its top or bottom, faster the closer it is.
  void _scrollIfAtEdge() {
    final step = _scrollStep();
    if (step == 0) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
      return;
    }
    _scrollTimer ??= Timer.periodic(tick, (_) {
      final position = _scrollable?.position;
      final step = _scrollStep();
      if (position == null || step == 0 || !isDragging) {
        _scrollTimer?.cancel();
        _scrollTimer = null;
        return;
      }
      final to = (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (to == position.pixels) return;
      position.jumpTo(to);
      // The tiles moved under a pointer that did not, so look again once
      // they are laid out where they now are.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isDragging) _cover();
      });
    });
  }

  double _scrollStep() {
    final box = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    final y = box.globalToLocal(_lastAt).dy;
    final height = box.size.height;
    final band = math.min(edge, height / 4);
    if (y < band) return -maxScrollStep * (band - y).clamp(0, band) / band;
    if (y > height - band) {
      return maxScrollStep * (y - height + band).clamp(0, band) / band;
    }
    return 0;
  }
}

/// What a `PhotoGridDragTarget` tags its tile with, so a
/// [PhotoGridDragSelection] can tell which of its own tiles is under the
/// pointer.
@immutable
class PhotoGridDragTag {
  /// Tags the tile at [index] of [owner]'s grid.
  const PhotoGridDragTag(this.owner, this.index);

  /// The drag selection of the grid the tile belongs to.
  final PhotoGridDragSelection owner;

  /// The tile's index into the grid's photos.
  final int index;
}
