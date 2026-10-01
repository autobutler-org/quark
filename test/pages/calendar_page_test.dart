import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/pages/calendar_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Calendar page (#1148, #2519): its views at their own URLs, Week by
/// default, the date kept across switches, and the event form.
void main() {
  final settings = AppSettings.instance;
  final requests = <http.Request>[];
  final today = CalendarDates.dateOnly(DateTime.now());
  final todayKey = CalendarDates.key(today);

  /// Today at [hour], in UTC as the Quark sends it.
  String todayAt(int hour) => DateTime(
    today.year,
    today.month,
    today.day,
    hour,
  ).toUtc().toIso8601String();

  Map<String, Object?> event(int id, String title, int hour) => {
    'id': id,
    'calendarId': 1,
    'title': title,
    'notes': '',
    'location': '',
    'start': todayAt(hour),
    'end': todayAt(hour + 1),
    'allDay': false,
    'timeZone': '',
    'repeat': 'none',
    'reminderMinutes': null,
    'colorIndex': 0,
  };

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    requests.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v0/calendar/events') {
        if (request.method == 'POST') {
          return http.Response(jsonEncode(event(9, 'Dentist', 10)), 201);
        }
        return http.Response(
          jsonEncode({
            'events': [event(1, 'Plumber visit', 9)],
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
    await clearHosts();
  });

  Future<GoRouter> pumpCalendar(
    WidgetTester tester,
    String location,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final r = GoRouter(
      initialLocation: location,
      routes: tabbedRoutes(
        path: AppRoutes.calendar,
        tabs: CalendarView.values,
        keepQuery: true,
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
        if (view != CalendarView.upcoming) {
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
}
