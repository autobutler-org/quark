import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../models/calendar_event_item.dart';
import '../calendar_dates.dart';
import '../calendar_event_chip.dart';
import '../calendar_labels.dart';
import 'time_grid_event_semantics.dart';

/// Lets one event block on `CalendarTimeGrid` be moved and resized, by a drag
/// or from the keyboard (#2526).
///
/// Dragging [child] moves the event: down and up through the day, and across
/// to another of [days] when there is more than one. Dragging from the strip
/// along its bottom edge moves its end alone. Both go in [step]-minute steps.
/// With a mouse the drag starts at once and the strip is 8 pixels with a
/// resize cursor. On a touch platform (see [wantsTouchTargets]) the block is
/// held first, so a swipe over it still scrolls the timeline, and the strip
/// is the block's bottom 48dp, or its bottom half when it is shorter than
/// 96dp.
///
/// While a drag is in flight the block dims and [onPreview] is called with
/// the occurrence as it would land, for the grid to draw in whichever column
/// that is, then with null when the drag ends. Letting go anywhere new calls
/// [onReschedule].
///
/// With the block focused, Alt and an arrow do the same: up and down move it
/// a step, left and right a day, and with Shift held up and down move its
/// end. Each press calls [onReschedule] at once. A screen reader gets the
/// same moves as custom actions ("Move 15 minutes later", "Move to the next
/// day", "Extend by 15 minutes", and their opposites; no day moves on a
/// single date), the keys as the event's hint, and the new times announced
/// after each (#3185). A mouse hovering the event is told the keys in a
/// tooltip.
///
/// Nothing here animates: the preview jumps from step to step, so reduced
/// motion has nothing to drop. It is stateful only for the drag in flight.
///
/// It adds no keys of its own.
class TimeGridEventMover extends StatefulWidget {
  /// Wraps [child], the block drawn for [item].
  const TimeGridEventMover({
    required this.item,
    required this.days,
    required this.height,
    required this.hourHeight,
    required this.columnWidth,
    required this.onPreview,
    required this.onReschedule,
    required this.child,
    super.key,
  });

  /// The occurrence [child] draws.
  final CalendarEventItem item;

  /// The dates the grid shows, in order: as far as a move can carry the event.
  final List<DateTime> days;

  /// How tall [child] is drawn, which sizes the resize strip.
  final double height;

  /// The height of one hour on the timeline.
  final double hourHeight;

  /// The width of one day's column: how far sideways is one day.
  final double columnWidth;

  /// Called with [item] as a drag in flight would leave it, each time that
  /// changes, and with null when the drag ends or is called off.
  final ValueChanged<CalendarEventItem?> onPreview;

  /// Called with [item] at its new times when a drag is let go somewhere new,
  /// or a key press moved it. [fromKeyboard] says which.
  final void Function(CalendarEventItem moved, {required bool fromKeyboard})
  onReschedule;

  /// The block.
  final Widget child;

  /// The minutes one step of a drag or one key press moves an event.
  static const int step = 15;

  /// The keys, as the event's tooltip and its hint to a screen reader.
  static const String keysHint =
      'Alt+Up or Down moves it $step minutes, Alt+Left or Right a day, '
      'Alt+Shift+Up or Down its end';

  /// [item] moved [dayShift] dates and [minutes] minutes later, or with
  /// [resize] its end alone moved [minutes] later. Negative is earlier.
  ///
  /// Times move on the wall clock, so a move across a daylight saving change
  /// keeps the time of day. A move keeps the event's length; its start stays
  /// on its own date however far [minutes] reaches, and on one of [days]
  /// however far [dayShift] does, and does not change date at all when it is
  /// on none of them. A resize never leaves the event without length: it
  /// stops a step short of the start.
  static CalendarEventItem shift(
    CalendarEventItem item,
    List<DateTime> days, {
    int dayShift = 0,
    int minutes = 0,
    bool resize = false,
  }) {
    final start = item.start;
    final end = item.end;
    if (resize) {
      final length = end.difference(start).inMinutes;
      final by = math.max(minutes, -((length - 1) ~/ step) * step);
      return item.rescheduled(
        start,
        DateTime(end.year, end.month, end.day, end.hour, end.minute + by),
      );
    }
    final index = days.indexWhere((d) => CalendarDates.isSameDay(d, start));
    final byDays = index < 0
        ? 0
        : dayShift.clamp(-index, days.length - 1 - index);
    final startMinute = start.hour * 60 + start.minute;
    final by = minutes.clamp(
      -(startMinute ~/ step) * step,
      ((24 * 60 - step - startMinute) ~/ step) * step,
    );
    DateTime moved(DateTime t) =>
        DateTime(t.year, t.month, t.day + byDays, t.hour, t.minute + by);
    return item.rescheduled(moved(start), moved(end));
  }

  @override
  State<TimeGridEventMover> createState() => _TimeGridEventMoverState();
}

class _TimeGridEventMoverState extends State<TimeGridEventMover> {
  // Where the pointer went down, while a drag is in flight.
  Offset? _origin;
  bool _resize = false;
  CalendarEventItem? _preview;

  // Set while [_onEscape] is registered. A drag does not focus the block, so
  // Escape would otherwise never reach it, and letting go would still move
  // the event.
  bool _watchingEscape = false;

  /// 1 where a later day is to the right, -1 where it is to the left.
  int get _later => Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  double _handle(bool touch) =>
      math.min(touch ? kMinInteractiveDimension : 8, widget.height / 2);

  void _start(Offset global, Offset local, bool touch) {
    setState(() {
      _origin = global;
      _resize = local.dy >= widget.height - _handle(touch);
      _preview = null;
    });
    _watchEscape();
  }

  void _update(Offset global) {
    final origin = _origin;
    if (origin == null) return;
    final travel = global - origin;
    final preview = TimeGridEventMover.shift(
      widget.item,
      widget.days,
      dayShift: (travel.dx * _later / widget.columnWidth).round(),
      minutes:
          (travel.dy / widget.hourHeight * 60 / TimeGridEventMover.step)
              .round() *
          TimeGridEventMover.step,
      resize: _resize,
    );
    if (preview == _preview) return;
    _preview = preview;
    widget.onPreview(preview);
  }

  void _end() {
    if (_origin == null) return;
    final preview = _preview;
    _cancel();
    if (preview != null && preview != widget.item) {
      widget.onReschedule(preview, fromKeyboard: false);
    }
  }

  void _cancel() {
    if (_origin == null) return;
    _stopListeningForEscape();
    setState(() {
      _origin = null;
      _preview = null;
    });
    widget.onPreview(null);
  }

  void _watchEscape() {
    if (_watchingEscape) return;
    _watchingEscape = true;
    HardwareKeyboard.instance.addHandler(_onEscape);
  }

  void _stopListeningForEscape() {
    if (!_watchingEscape) return;
    _watchingEscape = false;
    HardwareKeyboard.instance.removeHandler(_onEscape);
  }

  // Escape calls the drag off. Key-up and every other key are left alone.
  bool _onEscape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    _cancel();
    return true;
  }

  @override
  void dispose() {
    _stopListeningForEscape();
    super.dispose();
  }

  void _nudge({int days = 0, int minutes = 0, bool resize = false}) {
    final moved = TimeGridEventMover.shift(
      widget.item,
      widget.days,
      dayShift: days,
      minutes: minutes,
      resize: resize,
    );
    if (moved == widget.item) return;
    widget.onReschedule(moved, fromKeyboard: true);
    final range = CalendarLabels.timeRange(
      moved.start,
      moved.end,
      use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        [
          moved.title,
          if (!CalendarDates.isSameDay(moved.start, widget.item.start))
            CalendarLabels.dayTitleShort(moved.start),
          range,
        ].join(', '),
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final touch = wantsTouchTargets(context);
    const step = TimeGridEventMover.step;
    // A mouse's drag, whichever way it sets off.
    final GestureDragStartCallback? dragStart = touch
        ? null
        : (d) => _start(d.globalPosition, d.localPosition, touch);
    final GestureDragUpdateCallback? dragUpdate = touch
        ? null
        : (d) => _update(d.globalPosition);
    final GestureDragEndCallback? dragEnd = touch ? null : (_) => _end();

    final mover = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _nudge(minutes: -step),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _nudge(minutes: step),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _nudge(days: -_later),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _nudge(days: _later),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          alt: true,
          shift: true,
        ): () =>
            _nudge(minutes: -step, resize: true),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          alt: true,
          shift: true,
        ): () =>
            _nudge(minutes: step, resize: true),
      },
      // A touch holds first, so a swipe still scrolls the timeline. A mouse
      // drags at once, on two one-way recognizers rather than a pan: an
      // inner sideways drag is what wins over a page's own sideways swipe.
      // Neither takes the drag's cancel: the way that lost reports one just
      // before the way that won starts.
      child: GestureDetector(
        // The block owns the label and the move actions. This detector's
        // long-press node does not merge with that transparent hit-test
        // node, so a touch hold would be an unlabeled target (#3251).
        excludeFromSemantics: true,
        dragStartBehavior: DragStartBehavior.down,
        onLongPressStart: touch
            ? (d) => _start(d.globalPosition, d.localPosition, touch)
            : null,
        onLongPressMoveUpdate: touch ? (d) => _update(d.globalPosition) : null,
        onLongPressEnd: touch ? (_) => _end() : null,
        onLongPressCancel: touch ? _cancel : null,
        onVerticalDragStart: dragStart,
        onVerticalDragUpdate: dragUpdate,
        onVerticalDragEnd: dragEnd,
        onHorizontalDragStart: dragStart,
        onHorizontalDragUpdate: dragUpdate,
        onHorizontalDragEnd: dragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: _origin == null ? 1 : 0.4, child: widget.child),
            if (!touch)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _handle(touch),
                // Not opaque, so a tap on the strip still opens the event.
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  opaque: false,
                ),
              ),
          ],
        ),
      ),
    );

    // On the block's node, not a parent one. A transparent hit-test node
    // does not merge, and a parent would leave the tap on a target the
    // pointer can hit (#3251).
    return TimeGridEventSemantics(
      hint: TimeGridEventMover.keysHint,
      actions: {
        const CustomSemanticsAction(label: 'Move $step minutes earlier'): () =>
            _nudge(minutes: -step),
        const CustomSemanticsAction(label: 'Move $step minutes later'): () =>
            _nudge(minutes: step),
        if (widget.days.length > 1) ...{
          const CustomSemanticsAction(label: 'Move to the previous day'): () =>
              _nudge(days: -1),
          const CustomSemanticsAction(label: 'Move to the next day'): () =>
              _nudge(days: 1),
        },
        const CustomSemanticsAction(label: 'Shorten by $step minutes'): () =>
            _nudge(minutes: -step, resize: true),
        const CustomSemanticsAction(label: 'Extend by $step minutes'): () =>
            _nudge(minutes: step, resize: true),
      },
      // A touch's hold is the drag, so only a mouse's hover shows the keys.
      child: touch
          ? mover
          : Tooltip(
              message: TimeGridEventMover.keysHint,
              triggerMode: TooltipTriggerMode.manual,
              excludeFromSemantics: true,
              child: mover,
            ),
    );
  }
}
