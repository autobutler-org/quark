import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/calendar/calendar_time_grid/time_grid_event_mover.dart';
import 'package:quark_widgets/src/calendar/calendar_time_grid/time_grid_hour_gutter.dart';
import 'package:quark_widgets/src/calendar/calendar_time_grid/time_grid_layout.dart';

import '../support/pump.dart';

/// The hourly timeline behind the Day and Week views.
final _today = DateTime(2026, 9, 29);
final _now = DateTime(2026, 9, 29, 15, 40);

CalendarEventItem _at(int id, String title, int hour, int minute, int length) {
  final start = DateTime(2026, 9, 29, hour, minute);
  return CalendarEventItem(
    eventId: id,
    title: title,
    start: start,
    end: start.add(Duration(minutes: length)),
  );
}

final _call = _at(1, 'Insurance call', 12, 0, 45);
final _lunch = _at(2, 'Lunch with Sam', 12, 30, 60);
final _vet = _at(3, 'Vet', 16, 0, 45);
final _garden = CalendarEventItem(
  eventId: 4,
  title: 'Garden waste pickup',
  start: _today,
  end: DateTime(2026, 9, 30),
  allDay: true,
);
final _blip = _at(8, 'Blip', 14, 0, 5);

/// Two more all-day events on [_today], enough with [_garden] to overflow
/// its cell into a "+N" line.
final _moreAllDay = [
  for (final (id, title) in [(9, 'Rent due'), (10, 'Bins out')])
    CalendarEventItem(
      eventId: id,
      title: title,
      start: _today,
      end: DateTime(2026, 9, 30),
      allDay: true,
    ),
];

Widget _grid({
  required List<DateTime> days,
  List<CalendarEventItem>? events,
  DateTime? now,
  ValueChanged<DateTime>? onSlotTap,
  ValueChanged<CalendarEventItem>? onEventTap,
  void Function(CalendarEventItem item, DateTime start, DateTime end)?
  onEventReschedule,
  ValueChanged<DateTime>? onDayTap,
  VoidCallback? onAddEvent,
  bool isLoading = false,
}) => CalendarTimeGrid(
  days: days,
  today: _today,
  now: now,
  initialHour: 11,
  events: events ?? [_call, _lunch, _vet, _garden],
  onSlotTap: onSlotTap,
  onEventTap: onEventTap,
  onEventReschedule: onEventReschedule,
  onDayTap: onDayTap,
  onAddEvent: onAddEvent,
  isLoading: isLoading,
);

void main() {
  group('layoutDay', () {
    test('splits overlapping events into lanes', () {
      final placed = {
        for (final p in layoutDay(_today, [_vet, _lunch, _call])) p.item: p,
      };
      expect(placed[_call]!.lanes, 2);
      expect(placed[_lunch]!.lanes, 2);
      expect({placed[_call]!.lane, placed[_lunch]!.lane}, {0, 1});
      expect(placed[_vet]!.lanes, 1);
      expect(placed[_vet]!.startMinute, 16 * 60);
      expect(placed[_vet]!.endMinute, 16 * 60 + 45);
    });

    test('clips an event across midnight to each day', () {
      final late = CalendarEventItem(
        eventId: 5,
        title: 'Late show',
        start: DateTime(2026, 9, 29, 23),
        end: DateTime(2026, 9, 30, 1),
      );
      final first = layoutDay(_today, [late]).single;
      expect((first.startMinute, first.endMinute), (23 * 60, 24 * 60));
      final second = layoutDay(DateTime(2026, 9, 30), [late]).single;
      expect((second.startMinute, second.endMinute), (0, 60));
    });

    test('draws a very short event tall enough to tap', () {
      final blip = _at(6, 'Blip', 9, 0, 5);
      final placed = layoutDay(_today, [blip]).single;
      expect(placed.endMinute - placed.startMinute, minimumBlockMinutes);
    });

    test('draws nothing shorter than the minimum it is asked for', () {
      final placed = layoutDay(_today, [_blip, _vet], minimumMinutes: 48);
      expect([
        for (final p in placed) p.endMinute - p.startMinute,
      ], everyElement(greaterThanOrEqualTo(48)));
      expect(placed.first.startMinute, 14 * 60);
    });

    test('backs a short event up from midnight to keep its height', () {
      final nightcap = _at(11, 'Nightcap', 23, 50, 10);
      final placed = layoutDay(_today, [nightcap], minimumMinutes: 48).single;
      expect((placed.startMinute, placed.endMinute), (24 * 60 - 48, 24 * 60));
    });

    test('numbers each group of overlapping events', () {
      final placed = {
        for (final p in layoutDay(_today, [_vet, _lunch, _call])) p.item: p,
      };
      expect(placed[_call]!.group, placed[_lunch]!.group);
      expect(placed[_vet]!.group, isNot(placed[_call]!.group));
    });

    test('skips all-day events and other dates', () {
      final tomorrow = CalendarEventItem(
        eventId: 7,
        title: 'Tomorrow',
        start: DateTime(2026, 9, 30, 9),
        end: DateTime(2026, 9, 30, 10),
      );
      expect(layoutDay(_today, [_garden, tomorrow]), isEmpty);
    });
  });

  testBothViewports('a day shows its events and its all-day row', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _grid(days: [_today], now: _now),
      size: size,
    );
    expect(find.text('Garden waste pickup'), findsOneWidget);
    expect(find.text('Insurance call'), findsOneWidget);
    expect(find.text('Lunch with Sam'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_now_line')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar_day_header_2026-09-29')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an empty day says it has no all-day events', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _grid(days: [_today], events: const []),
      size: size,
    );
    expect(find.text('No all-day events'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_now_line')), findsNothing);
  });

  testBothViewports('a week heads each column and taps through to a day', (
    tester,
    size,
  ) async {
    DateTime? opened;
    await pumpAt(
      tester,
      _grid(days: CalendarDates.weekOf(_today), onDayTap: (d) => opened = d),
      size: size,
    );
    for (final day in CalendarDates.weekOf(_today)) {
      expect(
        find.byKey(ValueKey('calendar_day_header_${CalendarDates.key(day)}')),
        findsOneWidget,
      );
    }
    expect(find.text('No all-day events'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('calendar_day_header_2026-10-01')),
    );
    expect(opened, DateTime(2026, 10, 1));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('an empty hour creates at that hour', (tester, size) async {
    DateTime? start;
    await pumpAt(
      tester,
      _grid(days: [_today], events: const [], onSlotTap: (s) => start = s),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_slot_2026-09-29_13')));
    expect(start, DateTime(2026, 9, 29, 13));
  });

  testBothViewports('an event block calls back with its occurrence', (
    tester,
    size,
  ) async {
    CalendarEventItem? tapped;
    await pumpAt(
      tester,
      _grid(days: [_today], onEventTap: (e) => tapped = e),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_event_2_2026-09-29')));
    expect(tapped, _lunch);
  });

  testWidgets('the now line only shows on its own date', (tester) async {
    await pumpAt(
      tester,
      _grid(days: [DateTime(2026, 9, 30)], now: _now),
      size: wideViewport,
    );
    expect(find.byKey(const ValueKey('calendar_now_line')), findsNothing);
  });

  testWidgets('a phone week keeps event titles and drops their times', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _grid(days: CalendarDates.weekOf(_today)),
      size: narrowViewport,
    );
    expect(find.text('Lunch with Sam'), findsOneWidget);
    expect(find.text('12:30 – 1:30 PM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('touch targets (#2939)', () {
    final week = CalendarDates.weekOf(_today);
    final crowd = find.byKey(const ValueKey('calendar_crowd_2026-09-29_720'));
    final lunch = find.byKey(const ValueKey('calendar_event_2_2026-09-29'));
    final blip = find.byKey(const ValueKey('calendar_event_8_2026-09-29'));

    for (final (name, days) in [
      ('week', week),
      ('day', [_today]),
    ]) {
      testBothViewports("a $name's slots, events, all-day lines and dates "
          'are labeled 48dp targets a screen reader can press', (
        tester,
        size,
      ) async {
        await pumpAt(
          tester,
          _grid(
            days: days,
            events: [_call, _lunch, _vet, _blip, _garden, ..._moreAllDay],
            onSlotTap: (_) {},
            onEventTap: (_) {},
            onDayTap: (_) {},
          ),
          size: size,
        );

        expect(
          find.byKey(const ValueKey('calendar_all_day_more_2026-09-29')),
          findsOneWidget,
        );
        await expectTapTargetGuidelines(tester);
      });
    }

    testBothViewports('a five-minute event is drawn a target tall', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        _grid(days: [_today], events: [_blip], onEventTap: (_) {}),
        size: size,
      );
      expect(
        tester.getSize(blip).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
    });

    testWidgets('a desktop draws a five-minute event to the mouse-sized '
        'minimum', (tester) async {
      await pumpAt(
        tester,
        _grid(days: [_today], events: [_blip], onEventTap: (_) {}),
      );
      expect(
        tester.getSize(blip).height,
        minimumBlockMinutes * 56 / 60 - blockGap,
      );
    }, variant: TargetPlatformVariant.desktop());

    testWidgets("a phone week's columns are each a target wide, with the "
        'hours in a narrow gutter', (tester) async {
      await pumpAt(
        tester,
        _grid(
          days: week,
          now: _now,
          onSlotTap: (_) {},
          onEventTap: (_) {},
          onDayTap: (_) {},
        ),
        size: narrowViewport,
      );
      // Measured, not left to the guideline, which skips the headers and the
      // last column for touching the screen's edge.
      for (final key in [
        for (final day in week)
          ValueKey('calendar_day_header_${CalendarDates.key(day)}'),
        const ValueKey('calendar_slot_2026-10-03_13'),
        const ValueKey('calendar_event_3_2026-09-29'),
        const ValueKey('calendar_event_4_2026-09-29'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(
          size.shortestSide,
          greaterThanOrEqualTo(kMinInteractiveDimension),
          reason: '$key is $size',
        );
      }
      expect(find.text('12p'), findsOneWidget);
      expect(find.text('12 PM'), findsNothing);
      // The now line stays; its time has no room in the gutter.
      expect(find.byKey(const ValueKey('calendar_now_line')), findsOneWidget);
      expect(find.text('3:40pm'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone day and a wide week keep the full hour labels', (
      tester,
    ) async {
      await pumpAt(tester, _grid(days: [_today]), size: narrowViewport);
      expect(find.text('12 PM'), findsOneWidget);
      await pumpAt(tester, _grid(days: week), size: wideViewport);
      expect(find.text('12 PM'), findsOneWidget);
    });

    testWidgets("a phone week's overlapping events share one target that "
        'opens the day', (tester) async {
      final opened = <DateTime>[];
      final events = <CalendarEventItem>[];
      await pumpAt(
        tester,
        _grid(days: week, onEventTap: events.add, onDayTap: opened.add),
        size: narrowViewport,
      );
      final handle = tester.ensureSemantics();

      expect(
        tester.getSemantics(crowd),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: '2 events, show Tuesday, September 29',
        ),
      );
      // The blocks still read, but neither is a button of its own.
      expect(
        tester.getSemantics(lunch),
        isSemantics(label: 'Lunch with Sam, 12:30 – 1:30 PM'),
      );
      handle.dispose();

      await tester.tap(lunch);
      expect(opened, [_today]);
      expect(events, isEmpty);
      // An event on its own in the column keeps its own tap.
      await tester.tap(
        find.byKey(const ValueKey('calendar_event_3_2026-09-29')),
      );
      expect(events, [_vet]);
    });

    testWidgets('overlapping events with room for a target each keep their '
        'own taps', (tester) async {
      final events = <CalendarEventItem>[];
      for (final (days, size) in [
        (week, wideViewport),
        ([_today], narrowViewport),
      ]) {
        await pumpAt(
          tester,
          _grid(days: days, onEventTap: events.add, onDayTap: (_) {}),
          size: size,
        );
        expect(crowd, findsNothing);
        await tester.tap(lunch);
      }
      expect(events, [_lunch, _lunch]);
    });

    testWidgets('a desktop week in a narrow window keeps its gutter, and '
        'leaves narrow lanes their own taps', (tester) async {
      final events = <CalendarEventItem>[];
      await pumpAt(
        tester,
        _grid(days: week, now: _now, onEventTap: events.add, onDayTap: (_) {}),
        size: narrowViewport,
      );
      expect(find.text('12 PM'), findsOneWidget);
      expect(find.text('3:40pm'), findsOneWidget);
      expect(crowd, findsNothing);
      await tester.tap(lunch);
      expect(events, [_lunch]);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a week with no day to open leaves narrow lanes their own '
        'taps', (tester) async {
      final events = <CalendarEventItem>[];
      await pumpAt(
        tester,
        _grid(days: week, onEventTap: events.add),
        size: narrowViewport,
      );
      expect(crowd, findsNothing);
      await tester.tap(lunch);
      expect(events, [_lunch]);
    });

    testWidgets('an all-day overflow line says what it opens', (tester) async {
      DateTime? opened;
      await pumpAt(
        tester,
        _grid(
          days: week,
          events: [_garden, ..._moreAllDay],
          onDayTap: (d) => opened = d,
        ),
        size: narrowViewport,
      );
      final handle = tester.ensureSemantics();
      final more = find.byKey(
        const ValueKey('calendar_all_day_more_2026-09-29'),
      );
      expect(
        tester.getSemantics(more),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: '2 more, show Tuesday, September 29',
        ),
      );
      handle.dispose();
      await tester.tap(more);
      expect(opened, _today);
    });

    testLargeText("a phone week's narrow gutter scales its labels down "
        'rather than clip them', (tester, size) async {
      await pumpAt(
        tester,
        _grid(days: week, onSlotTap: (_) {}, onDayTap: (_) {}),
        size: size,
      );
      expect(tester.takeException(), isNull);
      if (size == narrowViewport) {
        final gutter = tester.getSize(find.byType(TimeGridHourGutter)).width;
        for (final label in ['12p', 'All\nday']) {
          final box = find.ancestor(
            of: find.text(label),
            matching: find.byType(FittedBox),
          );
          expect(tester.getSize(box).width, lessThanOrEqualTo(gutter));
        }
      }
    });
  });

  group('an empty day (#2538)', () {
    testBothViewports('keeps its timeline and offers to add an event', (
      tester,
      size,
    ) async {
      var added = 0;
      DateTime? start;
      await pumpAt(
        tester,
        _grid(
          days: [_today],
          events: const [],
          onAddEvent: () => added++,
          onSlotTap: (s) => start = s,
        ),
        size: size,
      );
      expect(find.text('Free day'), findsOneWidget);
      expect(find.text('Nothing scheduled'), findsOneWidget);
      expect(find.text('No all-day events'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar_day_add')));
      expect(added, 1);
      // The hours around the notice still create at their hour.
      await tester.tap(
        find.byKey(const ValueKey('calendar_slot_2026-09-29_11')),
      );
      expect(start, DateTime(2026, 9, 29, 11));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-day event alone is not a free day', (tester) async {
      await pumpAt(
        tester,
        _grid(days: [_today], events: [_garden], onAddEvent: () {}),
      );
      expect(find.text('Free day'), findsNothing);
    });

    testWidgets('says nothing while loading, or across a week', (tester) async {
      await pumpAt(
        tester,
        _grid(
          days: [_today],
          events: const [],
          isLoading: true,
          onAddEvent: () {},
        ),
      );
      expect(find.text('Free day'), findsNothing);
      await pumpAt(
        tester,
        _grid(
          days: CalendarDates.weekOf(_today),
          events: const [],
          onAddEvent: () {},
        ),
      );
      expect(find.text('Free day'), findsNothing);
    });

    for (final size in [narrowViewport, wideViewport]) {
      testWidgets('survives text at twice the size at $size', (tester) async {
        await pumpAt(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: _grid(days: [_today], events: const [], onAddEvent: () {}),
            ),
          ),
          size: size,
        );
        expect(find.text('Free day'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testBothViewports('its button is a labeled, full-size target', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        _grid(days: [_today], events: const [], onAddEvent: () {}),
        size: size,
      );
      final handle = tester.ensureSemantics();
      final button = tester.getSize(
        find.byKey(const ValueKey('calendar_day_add')),
      );
      expect(button.height, greaterThanOrEqualTo(48));
      final semantics = tester
          .getSemantics(find.byKey(const ValueKey('calendar_day_add')))
          .getSemanticsData();
      expect(semantics.label, 'Add an event');
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });
  });

  // #2886: the dashed "New event at" hint is a live hover and nothing else. It
  // goes when the span changes under a resting pointer, stays off while a
  // button is held (a drag is a swipe, not a create), and goes once its slot
  // is tapped.
  group('the hover hint', () {
    int ghosts() => find
        .descendant(
          of: find.byType(CalendarTimeGrid),
          matching: find.byIcon(QuarkIcons.add_rounded),
        )
        .evaluate()
        .length;

    Offset slot(WidgetTester tester, DateTime day, int hour) =>
        tester.getCenter(
          find.byKey(ValueKey('calendar_slot_${CalendarDates.key(day)}_$hour')),
        );

    Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      addTearDown(mouse.removePointer);
      await tester.pump();
      return mouse;
    }

    testBothViewports('clears when the span changes', (tester, size) async {
      final week = CalendarDates.weekOf(_today);
      await pumpAt(
        tester,
        _grid(days: week, onSlotTap: (_) {}),
        size: size,
      );
      await mouseAt(tester, slot(tester, _today, 13));
      expect(ghosts(), 1);

      final next = [for (final d in week) CalendarDates.addDays(d, 7)];
      await pumpAt(
        tester,
        _grid(days: next, onSlotTap: (_) {}),
        size: size,
      );
      expect(ghosts(), 0);
    });

    testBothViewports('stays off while a button is held', (tester, size) async {
      await pumpAt(
        tester,
        _grid(days: CalendarDates.weekOf(_today), onSlotTap: (_) {}),
        size: size,
      );
      final start = slot(tester, DateTime(2026, 9, 27), 13);
      final mouse = await mouseAt(tester, start);
      await mouse.down(start);
      for (var i = 0; i < 8; i++) {
        await mouse.moveBy(Offset(size.width / 40, 0));
        await tester.pump();
        expect(ghosts(), 0);
      }
      await mouse.up();
      await tester.pump();
      expect(ghosts(), 0);

      // Moving again is a hover again.
      await mouse.moveBy(const Offset(0, 2));
      await tester.pump();
      expect(ghosts(), 1);
    });

    testBothViewports('clears when its slot is tapped', (tester, size) async {
      DateTime? tapped;
      await pumpAt(
        tester,
        _grid(
          days: CalendarDates.weekOf(_today),
          onSlotTap: (start) => tapped = start,
        ),
        size: size,
      );
      final at = slot(tester, _today, 13);
      final mouse = await mouseAt(tester, at);
      expect(ghosts(), 1);
      await mouse.down(at);
      await mouse.up();
      await tester.pump();
      expect(tapped, DateTime(2026, 9, 29, 13));
      expect(ghosts(), 0);
    });
  });

  group('move and resize (#2526)', () {
    final week = CalendarDates.weekOf(_today);
    final vet = find.byKey(const ValueKey('calendar_event_3_2026-09-29'));
    final preview = find.byKey(const ValueKey('calendar_drag_preview'));
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 9, day, hour, minute);

    /// A grid of [days] holding [_vet] alone, whose moves land in the list
    /// it returns.
    Future<List<(CalendarEventItem, DateTime, DateTime)>> pumpVet(
      WidgetTester tester,
      List<DateTime> days,
      Size size,
    ) async {
      final moves = <(CalendarEventItem, DateTime, DateTime)>[];
      await pumpAt(
        tester,
        _grid(
          days: days,
          events: [_vet],
          onEventTap: (_) {},
          onEventReschedule: (item, start, end) =>
              moves.add((item, start, end)),
        ),
        size: size,
      );
      return moves;
    }

    /// Presses [key] with Alt held, and Shift too with [shift].
    Future<void> altArrow(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      final held = [
        LogicalKeyboardKey.altLeft,
        if (shift) LogicalKeyboardKey.shiftLeft,
      ];
      for (final modifier in held) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in held.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pump();
    }

    group('TimeGridEventMover.shift', () {
      test('moves the start and the end by the same minutes', () {
        final moved = TimeGridEventMover.shift(_vet, week, minutes: -30);
        expect(moved.start, at(29, 15, 30));
        expect(moved.end, at(29, 16, 15));
        expect(moved.title, 'Vet');
      });

      test('keeps the start on a date on show', () {
        // Tuesday is the third of the week's seven dates.
        expect(
          TimeGridEventMover.shift(_vet, week, dayShift: 9).start,
          DateTime(2026, 10, 3, 16),
        );
        expect(
          TimeGridEventMover.shift(_vet, week, dayShift: -9).start,
          at(27, 16),
        );
        expect(
          TimeGridEventMover.shift(_vet, [_today], dayShift: 1).start,
          at(29, 16),
        );
        // An event that started before the span stays on its date.
        expect(
          TimeGridEventMover.shift(_vet, [at(30, 0)], dayShift: 1).start,
          at(29, 16),
        );
      });

      test('keeps the start on its own date', () {
        final up = TimeGridEventMover.shift(_vet, week, minutes: -24 * 60);
        expect(up.start, at(29, 0));
        expect(up.end, at(29, 0, 45));
        final down = TimeGridEventMover.shift(_vet, week, minutes: 24 * 60);
        expect(down.start, at(29, 23, 45));
        expect(down.end, at(30, 0, 30));
      });

      test('a resize moves the end alone and never reaches the start', () {
        final longer = TimeGridEventMover.shift(
          _vet,
          week,
          minutes: 30,
          resize: true,
        );
        expect(longer.start, at(29, 16));
        expect(longer.end, at(29, 17, 15));
        final shortest = TimeGridEventMover.shift(
          _vet,
          week,
          minutes: -600,
          resize: true,
        );
        expect(shortest.start, at(29, 16));
        expect(shortest.end, at(29, 16, 15));
        // Five minutes cannot lose a step.
        expect(
          TimeGridEventMover.shift(_blip, week, minutes: -15, resize: true),
          _blip,
        );
      });
    });

    testBothViewports('a held event drags to a new time in 15-minute steps', (
      tester,
      size,
    ) async {
      final moves = await pumpVet(tester, [_today], size);
      final hour = size == narrowViewport ? 64.0 : 56.0;
      final gesture = await tester.startGesture(
        tester.getTopLeft(vet) + const Offset(20, 8),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      // Just over half an hour, which is two steps.
      await gesture.moveBy(Offset(0, hour * 0.56));
      await tester.pump();
      expect(preview, findsOneWidget);
      expect(moves, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(preview, findsNothing);
      expect(moves, [(_vet, at(29, 16, 30), at(29, 17, 15))]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a hold on an event's bottom edge drags its end alone", (
      tester,
    ) async {
      final moves = await pumpVet(tester, [_today], narrowViewport);
      final gesture = await tester.startGesture(
        tester.getBottomLeft(vet) + const Offset(20, -6),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 32));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(moves, [(_vet, at(29, 16), at(29, 17, 15))]);
    });

    testWidgets('a swipe over an event scrolls and moves nothing', (
      tester,
    ) async {
      final moves = await pumpVet(tester, [_today], narrowViewport);
      final before = tester.getTopLeft(vet).dy;
      await tester.drag(vet, const Offset(0, -80));
      await tester.pump();
      expect(tester.getTopLeft(vet).dy, lessThan(before));
      expect(moves, isEmpty);
    });

    testWidgets('a held event let go where it was moves nothing', (
      tester,
    ) async {
      final moves = await pumpVet(tester, [_today], narrowViewport);
      final gesture = await tester.startGesture(tester.getCenter(vet));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 4));
      await gesture.up();
      await tester.pump();
      expect(moves, isEmpty);
      expect(preview, findsNothing);
    });

    testWidgets('a mouse drags an event to another day and time at once', (
      tester,
    ) async {
      final moves = await pumpVet(tester, week, wideViewport);
      final column = tester.getSize(
        find.byKey(const ValueKey('calendar_slot_2026-09-29_16')),
      );
      final gesture = await tester.startGesture(
        tester.getTopLeft(vet) + const Offset(20, 8),
        kind: PointerDeviceKind.mouse,
      );
      // In two moves, as a hand makes many: the move that starts a drag
      // reports only the way that won it.
      await gesture.moveBy(Offset(column.width / 2, 14));
      await gesture.moveBy(Offset(column.width / 2, 14));
      await tester.pump();
      expect(
        tester.getTopLeft(preview).dx,
        greaterThan(tester.getTopRight(vet).dx),
      );
      await gesture.up();
      await tester.pump();
      expect(moves, [(_vet, at(30, 16, 30), at(30, 17, 15))]);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets("a mouse drags an event's bottom edge to resize it", (
      tester,
    ) async {
      final moves = await pumpVet(tester, week, wideViewport);
      final gesture = await tester.startGesture(
        tester.getBottomLeft(vet) + const Offset(20, -3),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -28));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(moves, [(_vet, at(29, 16), at(29, 16, 15))]);
    }, variant: TargetPlatformVariant.desktop());

    testBothViewports('Alt and an arrow move the focused event, and with '
        'Shift its end', (tester, size) async {
      final moves = await pumpVet(tester, [_today], size);
      Focus.of(tester.element(find.text('Vet'))).requestFocus();
      await tester.pump();

      await altArrow(tester, LogicalKeyboardKey.arrowDown);
      await altArrow(tester, LogicalKeyboardKey.arrowUp);
      await altArrow(tester, LogicalKeyboardKey.arrowDown, shift: true);
      await altArrow(tester, LogicalKeyboardKey.arrowUp, shift: true);
      // A Day has no other date to move to.
      await altArrow(tester, LogicalKeyboardKey.arrowRight);
      expect(moves, [
        (_vet, at(29, 16, 15), at(29, 17)),
        (_vet, at(29, 15, 45), at(29, 16, 30)),
        (_vet, at(29, 16), at(29, 17)),
        (_vet, at(29, 16), at(29, 16, 30)),
      ]);
    });

    testWidgets('the focus follows an event the keys move to another day', (
      tester,
    ) async {
      var events = [_vet];
      await pumpAt(
        tester,
        StatefulBuilder(
          builder: (context, setState) => _grid(
            days: week,
            events: events,
            onEventTap: (_) {},
            onEventReschedule: (item, start, end) =>
                setState(() => events = [item.rescheduled(start, end)]),
          ),
        ),
        size: wideViewport,
      );
      Focus.of(tester.element(find.text('Vet'))).requestFocus();
      await tester.pump();

      await altArrow(tester, LogicalKeyboardKey.arrowRight);
      await altArrow(tester, LogicalKeyboardKey.arrowRight);
      await altArrow(tester, LogicalKeyboardKey.arrowLeft);
      await altArrow(tester, LogicalKeyboardKey.arrowDown);
      expect(events.single.start, at(30, 16, 15));
      expect(
        find.byKey(const ValueKey('calendar_event_3_2026-09-30')),
        findsOneWidget,
      );
    });

    testWidgets('without a handler an event stays where it is', (tester) async {
      await pumpAt(
        tester,
        _grid(days: [_today], events: [_vet], onEventTap: (_) {}),
        size: narrowViewport,
      );
      expect(find.byType(TimeGridEventMover), findsNothing);
      final gesture = await tester.startGesture(tester.getCenter(vet));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 64));
      await tester.pump();
      expect(preview, findsNothing);
      await gesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
