import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/calendar_view.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/settings/settings_general_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2521: the General tab's "Calendar opens on" dropdown and the setting it
/// saves.
void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const dropdown = ValueKey('settings_calendar_view');
  final hosts = jsonEncode([
    {'name': 'One', 'hostAddress': 'http://one.local'},
  ]);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    // The tab's host manager reads the saved hosts.
    SharedPreferences.setMockInitialValues({'hosts': hosts});
    await AppSettings.instance.load();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    required Size size,
    CalendarView view = CalendarView.week,
    ValueChanged<CalendarView>? onChanged,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SettingsGeneralTab(
            theme: ThemeMode.system,
            onThemeChanged: (_) {},
            themeColor: QuarkThemeColor.classic,
            followsQuarkThemeColor: true,
            quarkThemeColor: QuarkThemeColor.classic,
            defaultCalendarView: view,
            onDefaultCalendarViewChanged: onChanged,
            refreshIntervalSeconds: 15,
            onRefreshIntervalChanged: (_) {},
            demoMode: false,
            onDemoModeChanged: (_) {},
            onHostsChanged: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder shown(String label) =>
      find.descendant(of: find.byKey(dropdown), matching: find.text(label));

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: the dropdown shows the saved view', (tester) async {
      await pumpTab(
        tester,
        size: size,
        view: CalendarView.month,
        onChanged: (_) {},
      );

      expect(find.text('Calendar opens on'), findsOneWidget);
      expect(shown('Month'), findsOneWidget);
      expect(shown('Week'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: picking a view reports it', (tester) async {
      CalendarView? reported;
      await pumpTab(tester, size: size, onChanged: (v) => reported = v);

      await tester.ensureVisible(find.byKey(dropdown));
      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      // The open menu lists the views in the calendar switch's order.
      final menu = find.byType(DropdownMenuItem<CalendarView>);
      expect(
        [
          for (final item in tester.widgetList<DropdownMenuItem>(menu))
            item.value,
        ],
        containsAllInOrder([
          CalendarView.day,
          CalendarView.week,
          CalendarView.month,
          CalendarView.upcoming,
        ]),
      );
      await tester.tap(find.text('Upcoming').last);
      await tester.pumpAndSettle();

      expect(reported, CalendarView.upcoming);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('without a handler there is no dropdown', (tester) async {
    await pumpTab(tester, size: const Size(1280, 800));

    expect(find.byKey(dropdown), findsNothing);
    expect(find.text('Calendar opens on'), findsNothing);
  });

  test('the setting is Week by default and survives a reload', () async {
    final settings = AppSettings.instance;
    expect(settings.defaultCalendarView.value, CalendarView.week);

    await settings.setDefaultCalendarView(CalendarView.month);
    settings.defaultCalendarView.value = CalendarView.week;
    await settings.load();

    expect(settings.defaultCalendarView.value, CalendarView.month);
  });

  test('a stored view the app does not know falls back to Week', () async {
    SharedPreferences.setMockInitialValues({
      'hosts': hosts,
      'defaultCalendarView': 'year',
    });
    AppSettings.instance.defaultCalendarView.value = CalendarView.month;
    await AppSettings.instance.load();

    expect(AppSettings.instance.defaultCalendarView.value, CalendarView.week);
  });
}
