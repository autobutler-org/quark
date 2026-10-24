import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/pages/calendar_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// The Calendar page (#1148, #2519): its views at their own URLs, Week by
/// default or the view chosen in Settings (#2521), the date kept across
/// switches, the event form, and weeks that start where the device's locale
/// says (#2539).
void main() {
  final settings = AppSettings.instance;
  final requests = <http.Request>[];
  final today = CalendarDates.dateOnly(DateTime.now());
  final todayKey = CalendarDates.key(today);

  /// What the Quark answers a save over an existing event with.
  var updateStatus = 200;

  /// How the plumber's visit, event 1, repeats.
  var plumberRepeat = 'none';

  /// The plumber's visit as the last save left it, or null for as it began.
  Map<String, Object?>? plumberSaved;

  /// Today at [hour], in UTC as the Quark sends it.
  String todayAt(int hour) => DateTime(
    today.year,
    today.month,
    today.day,
    hour,
  ).toUtc().toIso8601String();

  Map<String, Object?> event(
    int id,
    String title,
    int hour, {
    String owner = 'me',
    bool mine = true,
    String repeat = 'none',
  }) => {
    'owner': owner,
    'mine': mine,
    'id': id,
    'calendarId': 1,
    'title': title,
    'notes': '',
    'location': '',
    'start': todayAt(hour),
    'end': todayAt(hour + 1),
    'allDay': false,
    'timeZone': '',
    'repeat': repeat,
    'reminderMinutes': null,
    'colorIndex': 0,
  };

  Map<String, Object?> plumber() =>
      plumberSaved ?? event(1, 'Plumber visit', 9, repeat: plumberRepeat);

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    // A save asks the platform for its zone (#3732). Unanswered, that call
    // never completes inside a widget test, and the save never sends.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.autobutler.quark/time_zone'),
          (_) async => 'America/Los_Angeles',
        );
    requests.clear();
    updateStatus = 200;
    plumberRepeat = 'none';
    plumberSaved = null;
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v0/admin/users') {
        return http.Response(
          jsonEncode([
            {'id': 1, 'username': 'me', 'status': 'active'},
            {'id': 2, 'username': 'sam', 'status': 'active'},
            {'id': 3, 'username': 'newbie', 'status': 'pending'},
          ]),
          200,
        );
      }
      if (request.url.path == '/api/v0/calendar/events/1/move') {
        if (updateStatus != 200) {
          return http.Response('{"error":"no"}', updateStatus);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final series = {
          ...plumber(),
          'start': body['start'],
          'end': body['end'],
        };
        plumberSaved = series;
        final created = body['scope'] == 'all'
            ? null
            : event(9, 'Plumber visit', 9);
        return http.Response(
          jsonEncode({'series': series, 'created': ?created}),
          200,
        );
      }
      if (request.method == 'DELETE' &&
          request.url.path.startsWith('/api/v0/calendar/events/')) {
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v0/calendar/events/1') {
        if (request.method == 'PUT' && updateStatus == 200) {
          plumberSaved = {
            ...plumber(),
            ...jsonDecode(request.body) as Map<String, dynamic>,
          };
        }
        return http.Response(jsonEncode(plumber()), updateStatus);
      }
      if (request.url.path == '/api/v0/calendar/events') {
        if (request.method == 'POST') {
          return http.Response(jsonEncode(event(9, 'Dentist', 10)), 201);
        }
        return http.Response(
          jsonEncode({
            'events': [
              plumber(),
              event(2, 'Soccer practice', 13, owner: 'sam', mine: false),
            ],
          }),
          200,
        );
      }
      return http.Response('', 404);
    });
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
  });

  tearDown(() async {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    settings.defaultCalendarView.value = CalendarView.week;
    await clearHosts();
  });

  Future<GoRouter> pumpCalendar(
    WidgetTester tester,
    String location,
    Size size, {
    GoRouterRedirect? redirect,
  }) async {
    setViewport(tester, size);

    final r = GoRouter(
      initialLocation: location,
      redirect: redirect,
      routes: tabbedRoutes(
        path: AppRoutes.calendar,
        tabs: CalendarView.values,
        keepQuery: true,
        initialTab: () => settings.defaultCalendarView.value,
        builder: (view, onViewSelected) =>
            CalendarPage(view: view, onViewSelected: onViewSelected),
      ),
    );
    addTearDown(r.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        routerConfig: r,
      ),
    );
    await tester.pumpAndSettle();
    return r;
  }

  String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

  List<http.Request> listCalls() => [
    for (final r in requests)
      if (r.method == 'GET' && r.url.path == '/api/v0/calendar/events') r,
  ];

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: /calendar opens on this week', (tester) async {
      final r = await pumpCalendar(tester, AppRoutes.calendar, size);

      expect(at(r), '/calendar/week');
      expect(find.text('Calendar'), findsOneWidget);
      expect(
        find.byKey(ValueKey('calendar_day_header_$todayKey')),
        findsOneWidget,
      );
      expect(find.text('Plumber visit'), findsOneWidget);
      expect(listCalls(), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: /calendar opens on the view chosen in Settings', (
      tester,
    ) async {
      settings.defaultCalendarView.value = CalendarView.month;
      final r = await pumpCalendar(tester, AppRoutes.calendar, size);

      expect(at(r), '/calendar/month');
      expect(tester.takeException(), isNull);

      // A link naming a view still wins.
      r.go(AppRoutes.calendarView(CalendarView.day));
      await tester.pumpAndSettle();
      expect(at(r), '/calendar/day');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: each view renders without overflow', (tester) async {
      for (final view in CalendarView.values) {
        await pumpCalendar(
          tester,
          AppRoutes.calendarView(view, date: today),
          size,
        );
        expect(tester.takeException(), isNull, reason: view.slug);
        // Upcoming leaves out timed events already over, and a 9 AM one is
        // over for most of the day.
        // A phone's month marks events with dots rather than clipped
        // titles (#2541).
        if (view == CalendarView.month && name == 'narrow') {
          expect(
            find.byKey(ValueKey('calendar_dots_$todayKey')),
            findsOneWidget,
          );
          expect(find.text('Plumber visit'), findsNothing);
        } else if (view != CalendarView.upcoming) {
          expect(find.text('Plumber visit'), findsOneWidget, reason: view.slug);
        }
      }
    });

    testWidgets('$name: the arrows step and the URL follows', (tester) async {
      final r = await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.day, date: DateTime(2026, 9, 29)),
        size,
      );
      await tester.tap(find.byKey(const ValueKey('calendar_next')));
      await tester.pumpAndSettle();
      expect(at(r), '/calendar/day?date=2026-09-30');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('calendar_prev')));
        await tester.pumpAndSettle();
      }
      expect(at(r), '/calendar/day?date=2026-09-28');
    });

    // #2888: the app's router asks the Quark whether the calendar is on before
    // every calendar URL, so a step waits a round trip for its route. The
    // arrows step the page at once and the URL catches up, so the heading and
    // the grid move together on the tap rather than after the probe.
    testWidgets('$name: the arrows step at once and the URL follows (#2888)', (
      tester,
    ) async {
      const probe = Duration(milliseconds: 500);
      final r = await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week, date: DateTime(2026, 10, 7)),
        size,
        redirect: (_, _) async {
          await Future<void>.delayed(probe);
          return null;
        },
      );
      await tester.pump(probe);
      await tester.pumpAndSettle();

      String heading() => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(CalendarPeriodHeader),
              matching: find.byType(Text),
            ),
          )
          .data!;
      String week(int from, int to) => CalendarLabels.range(
        DateTime(2026, 10, from),
        DateTime(2026, 10, to),
        short: size.width < QuarkAppBarBottom.collapseBreakpoint,
      );

      expect(heading(), week(4, 10));
      await tester.tap(find.byKey(const ValueKey('calendar_next')));
      await tester.pump();
      expect(heading(), week(11, 17));
      expect(
        find.byKey(const ValueKey('calendar_day_header_2026-10-11')),
        findsOneWidget,
      );

      // A second step before the first route lands goes on from it.
      await tester.tap(find.byKey(const ValueKey('calendar_next')));
      await tester.pump();
      expect(heading(), week(18, 24));
      await tester.pump(probe * 2);
      await tester.pumpAndSettle();
      expect(heading(), week(18, 24));
      expect(at(r), '/calendar/week?date=2026-10-21');
    });

    testWidgets('$name: New event opens the form and saves it', (tester) async {
      final r = await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.month, date: DateTime(2027, 3, 12)),
        size,
      );
      await tester.tap(find.byKey(const ValueKey('calendar_new_event')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CalendarEventEditor),
          matching: find.text('New event'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('event_title')),
        'Dentist',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('event_save')));
      await tester.pumpAndSettle();

      final post = requests.singleWhere((q) => q.method == 'POST');
      expect(jsonDecode(post.body)['title'], 'Dentist');
      expect(find.byType(CalendarEventEditor), findsNothing);
      // #320: saving leaves the month on screen where it was.
      expect(at(r), '/calendar/month?date=2027-03-12');
    });

    testWidgets('$name: Save stays off until there is a title', (tester) async {
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week),
        size,
      );
      await tester.tap(find.byKey(const ValueKey('calendar_new_event')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('event_save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarEventEditor), findsOneWidget);
      expect(requests.where((q) => q.method == 'POST'), isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('event_title')),
        'Dentist',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    testWidgets('$name: tapping an event opens it for editing', (tester) async {
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.day, date: today),
        size,
      );
      await tester.tap(find.byKey(ValueKey('calendar_event_1_$todayKey')));
      await tester.pumpAndSettle();
      expect(find.text('Edit event'), findsOneWidget);
      expect(find.byKey(const ValueKey('event_delete')), findsOneWidget);
    });
  }

  group('dragging an event (#2526)', () {
    final plumber = find.byKey(ValueKey('calendar_event_1_$todayKey'));
    // Toward the middle of the week, so the day beside today is on show
    // whatever day the test runs.
    final way = CalendarDates.isSameDay(today, CalendarDates.weekOf(today).last)
        ? -1
        : 1;

    /// Drags the plumber's visit one day [way] with a mouse.
    Future<void> dragADay(WidgetTester tester) async {
      final column = tester.getSize(
        find.byKey(ValueKey('calendar_slot_${todayKey}_9')),
      );
      final mouse = await tester.startGesture(
        tester.getTopLeft(plumber) + const Offset(20, 8),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 4; i++) {
        await mouse.moveBy(Offset(way * column.width / 4, 0));
        await tester.pump();
      }
      await mouse.up();
      await tester.pumpAndSettle();
    }

    testWidgets('sideways in Week saves it a day on, and the week stays', (
      tester,
    ) async {
      final r = await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week),
        const Size(1280, 800),
      );
      await dragADay(tester);

      final save = requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(save.body) as Map<String, dynamic>;
      DateTime beside(int hour) =>
          DateTime(today.year, today.month, today.day + way, hour);
      expect(body['start'], beside(9).toUtc().toIso8601String());
      expect(body['end'], beside(10).toUtc().toIso8601String());
      expect(body['title'], 'Plumber visit');
      // The swipe that steps a week did not take the drag.
      expect(at(r), '/calendar/week');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a drag says where the event went, and Undo puts it back '
        '(#3184)', (tester) async {
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week),
        const Size(1280, 800),
      );
      await dragADay(tester);
      final beside = DateTime(today.year, today.month, today.day + way, 9);
      expect(
        find.text(
          'Moved to ${CalendarLabels.weekdayShort(beside.weekday)} '
          '9:00 AM',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('calendar_move_undo')));
      await tester.pumpAndSettle();
      final saves = requests.where((r) => r.method == 'PUT').toList();
      expect(saves, hasLength(2));
      final body = jsonDecode(saves.last.body) as Map<String, dynamic>;
      expect(body['start'], todayAt(9));
      expect(body['end'], todayAt(10));
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a repeating event asks which occurrences move (#3215)', (
      tester,
    ) async {
      plumberRepeat = 'weekly';

      // Each choice starts from the visit where it began. "This event" skips
      // the dragged day, so a later drag cannot look for that same chip.
      Future<void> dragAndTap(String key) async {
        requests.clear();
        plumberSaved = null;
        await pumpCalendar(
          tester,
          AppRoutes.calendarView(CalendarView.week),
          const Size(1280, 800),
        );
        await dragADay(tester);
        expect(
          find.byKey(const ValueKey('calendar_move_this')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('calendar_move_following')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('calendar_move_all')), findsOneWidget);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await dragAndTap('calendar_move_cancel');
      expect(requests.where((r) => r.url.path.endsWith('/move')), isEmpty);
      expect(plumber, findsOneWidget);

      for (final (key, scope) in [
        ('calendar_move_this', 'one'),
        ('calendar_move_following', 'following'),
        ('calendar_move_all', 'all'),
      ]) {
        await dragAndTap(key);
        final body =
            jsonDecode(
                  requests.lastWhere((r) => r.url.path.endsWith('/move')).body,
                )
                as Map<String, dynamic>;
        expect(body['scope'], scope, reason: key);
        expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      }
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('Ctrl+Z puts a repeating move back (#3215)', (tester) async {
      plumberRepeat = 'weekly';
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week),
        const Size(1280, 800),
      );
      await dragADay(tester);
      await tester.tap(find.byKey(const ValueKey('calendar_move_all')));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final restore = requests.lastWhere((r) => r.method == 'PUT');
      final body = jsonDecode(restore.body) as Map<String, dynamic>;
      expect(body['start'], todayAt(9));
      expect(body['end'], todayAt(10));
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('narrow: the move question fits and Cancel leaves it', (
      tester,
    ) async {
      plumberRepeat = 'weekly';
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.day, date: today),
        const Size(360, 640),
      );
      final finger = await tester.startGesture(
        tester.getTopLeft(plumber) + const Offset(20, 8),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await finger.moveBy(const Offset(0, 32));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('calendar_move_following')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar_move_cancel')));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.url.path.endsWith('/move')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a move the Quark refuses says so and goes back', (
      tester,
    ) async {
      updateStatus = 500;
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week),
        const Size(1280, 800),
      );
      await dragADay(tester);

      expect(
        find.text(
          Errors.message(const ApiException(500, ''), 'move the event'),
        ),
        findsOneWidget,
      );
      expect(plumber, findsOneWidget);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('narrow: a held event drags to a later time', (tester) async {
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.day, date: today),
        const Size(360, 640),
      );
      final finger = await tester.startGesture(
        tester.getTopLeft(plumber) + const Offset(20, 8),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await finger.moveBy(const Offset(0, 32));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      final save = requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(save.body) as Map<String, dynamic>;
      expect(
        body['start'],
        DateTime(
          today.year,
          today.month,
          today.day,
          9,
          30,
        ).toUtc().toIso8601String(),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('wide: switching views keeps the date', (tester) async {
    final r = await pumpCalendar(
      tester,
      AppRoutes.calendarView(CalendarView.day, date: DateTime(2026, 9, 29)),
      const Size(1280, 800),
    );
    await tester.tap(find.byKey(const ValueKey('bar_segment_month')));
    await tester.pumpAndSettle();
    expect(at(r), '/calendar/month?date=2026-09-29');
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('narrow: the view menu switches views and goes to today', (
    tester,
  ) async {
    final r = await pumpCalendar(
      tester,
      AppRoutes.calendarView(CalendarView.month, date: DateTime(2026, 9, 29)),
      const Size(360, 640),
    );
    await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar_menu_week')));
    await tester.pumpAndSettle();
    expect(at(r), '/calendar/week?date=2026-09-29');

    await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar_menu_today')));
    await tester.pumpAndSettle();
    expect(at(r), '/calendar/week?date=$todayKey');
  });

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: My events hides everyone else (#2544)', (tester) async {
      final r = await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.day, date: today),
        size,
      );
      expect(find.text('Soccer practice'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('calendar_filter_mine')));
      await tester.pumpAndSettle();
      expect(at(r), '/calendar/day?date=$todayKey&mine=true');
      expect(find.text('Plumber visit'), findsOneWidget);
      expect(find.text('Soccer practice'), findsNothing);

      // The filter stays through a step and a view switch.
      await tester.tap(find.byKey(const ValueKey('calendar_next')));
      await tester.pumpAndSettle();
      expect(at(r), contains('mine=true'));

      await tester.tap(find.byKey(const ValueKey('calendar_filter_everyone')));
      await tester.pumpAndSettle();
      expect(at(r), isNot(contains('mine')));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a person in the URL narrows to their events', (tester) async {
    await pumpCalendar(
      tester,
      '${AppRoutes.calendarView(CalendarView.day, date: today)}&person=sam',
      const Size(1280, 800),
    );
    expect(find.text('Soccer practice'), findsOneWidget);
    expect(find.text('Plumber visit'), findsNothing);
  });

  testWidgets('an admin picks one person from the active accounts', (
    tester,
  ) async {
    settings.isAdmin.value = true;
    addTearDown(() => settings.isAdmin.value = false);
    final r = await pumpCalendar(
      tester,
      AppRoutes.calendarView(CalendarView.day, date: today),
      const Size(1280, 800),
    );
    await tester.tap(find.byKey(const ValueKey('calendar_filter_people')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar_filter_person_newbie')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('calendar_filter_person_sam')));
    await tester.pumpAndSettle();
    expect(at(r), '/calendar/day?date=$todayKey&person=sam');
    expect(find.text('Soccer practice'), findsOneWidget);
    expect(find.text('Plumber visit'), findsNothing);
  });

  testWidgets('a non-admin gets no person picker', (tester) async {
    await pumpCalendar(
      tester,
      AppRoutes.calendarView(CalendarView.week),
      const Size(1280, 800),
    );
    expect(find.byKey(const ValueKey('calendar_filter_mine')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_filter_people')), findsNothing);
  });

  testWidgets('a month date opens that day', (tester) async {
    final r = await pumpCalendar(
      tester,
      AppRoutes.calendarView(CalendarView.month, date: DateTime(2026, 9, 29)),
      const Size(1280, 800),
    );
    await tester.tap(find.byKey(const ValueKey('calendar_day_2026-09-15')));
    await tester.pumpAndSettle();
    expect(at(r), '/calendar/day?date=2026-09-15');
  });

  testWidgets('an unknown view falls back to Week with the date kept', (
    tester,
  ) async {
    final r = await pumpCalendar(
      tester,
      '/calendar/year?date=2026-09-29',
      const Size(1280, 800),
    );
    expect(at(r), '/calendar/week?date=2026-09-29');
  });

  group('week start follows the device locale (#2539)', () {
    void deviceLocale(WidgetTester tester, Locale locale) {
      tester.platformDispatcher.localeTestValue = locale;
      tester.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    /// The local date the last events load started from.
    DateTime loadedFrom() =>
        DateTime.parse(listCalls().last.url.queryParameters['from']!).toLocal();

    for (final (name, size) in [
      ('narrow', const Size(360, 640)),
      ('wide', const Size(1280, 800)),
    ]) {
      testWidgets('$name: a Monday-first device starts the week on Monday', (
        tester,
      ) async {
        deviceLocale(tester, const Locale('de', 'DE'));
        await pumpCalendar(
          tester,
          AppRoutes.calendarView(
            CalendarView.week,
            date: DateTime(2026, 9, 29),
          ),
          size,
        );
        expect(
          find.byKey(const ValueKey('calendar_day_header_2026-09-28')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('calendar_day_header_2026-09-27')),
          findsNothing,
        );
        expect(loadedFrom(), DateTime(2026, 9, 28));
      });

      testWidgets('$name: a Monday-first device starts month rows on Monday', (
        tester,
      ) async {
        deviceLocale(tester, const Locale('en', 'GB'));
        await pumpCalendar(
          tester,
          AppRoutes.calendarView(
            CalendarView.month,
            date: DateTime(2026, 9, 29),
          ),
          size,
        );
        expect(
          find.byKey(const ValueKey('calendar_day_2026-08-31')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('calendar_day_2026-08-30')),
          findsNothing,
        );
        expect(loadedFrom(), DateTime(2026, 8, 31));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a Saturday-first device starts the week on Saturday', (
      tester,
    ) async {
      deviceLocale(tester, const Locale('fa', 'IR'));
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.week, date: DateTime(2026, 9, 29)),
        const Size(1280, 800),
      );
      expect(
        find.byKey(const ValueKey('calendar_day_header_2026-09-26')),
        findsOneWidget,
      );
      expect(loadedFrom(), DateTime(2026, 9, 26));
    });

    testWidgets('a US device keeps Sunday', (tester) async {
      deviceLocale(tester, const Locale('en', 'US'));
      await pumpCalendar(
        tester,
        AppRoutes.calendarView(CalendarView.month, date: DateTime(2026, 9, 29)),
        const Size(1280, 800),
      );
      expect(
        find.byKey(const ValueKey('calendar_day_2026-08-30')),
        findsOneWidget,
      );
      expect(loadedFrom(), DateTime(2026, 8, 30));
    });
  });
}
