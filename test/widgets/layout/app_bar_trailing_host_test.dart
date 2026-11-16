import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2493: the app-wide scope puts the notifications bell in every page's
/// bar, and the bell opens a route through the root's `onNavigate`. A
/// phone's bar has the account button instead, whose sheet holds the same
/// notifications (#4150).
void main() {
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('every bar reaches the notifications (${size.width})', (
      tester,
    ) async {
      setViewport(tester, size);
      final session = ValueNotifier<String?>('token');
      final jobs = JobsController(
        listJobs: ({required kinds}) async => const [],
        events: () => const Stream<FileEvent>.empty(),
        session: () => session,
      );
      final notifications = NotificationsController(
        listNotifications: () async => const [
          AppNotification(
            type: NotificationType.backupDue,
            link: '/system/storage',
          ),
        ],
        readDisabled: () async => {},
        saveEnabled: (_, _) async => {},
        events: () => const Stream<FileEvent>.empty(),
        session: () => session,
      )..start();
      final connection = ConnectionController();
      addTearDown(jobs.dispose);
      addTearDown(notifications.dispose);
      addTearDown(connection.dispose);
      final routes = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          builder: (context, child) => AppBarTrailingHost(
            jobs: jobs,
            connection: connection,
            notifications: notifications,
            onNavigate: routes.add,
            child: child!,
          ),
          home: const Scaffold(
            appBar: QuarkAppBar(label: 'Files', icon: QuarkIcons.folder),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final phone = size.width < QuarkAppBar.compactBreakpoint;
      if (phone) {
        expect(find.byKey(const ValueKey('notifications_bell')), findsNothing);
        expect(find.byTooltip('Account, something new'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('account_button')));
      } else {
        expect(find.byKey(const ValueKey('account_button')), findsNothing);
        // Every page's own theme toggle moved here (#4150).
        expect(find.byKey(const ValueKey('theme_toggle')), findsOneWidget);
        expect(find.byTooltip('1 notification'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('notifications_bell')));
      }
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('notification_tile_backup_due')),
      );
      await tester.pumpAndSettle();
      expect(routes, ['/system/storage']);
    });
  }

  testWidgets('the phone account sheet opens the jobs and the Quarks', (
    tester,
  ) async {
    setViewport(tester, const Size(390, 844));
    final session = ValueNotifier<String?>('token');
    final jobs = JobsController(
      listJobs: ({required kinds}) async => const [],
      events: () => const Stream<FileEvent>.empty(),
      session: () => session,
    );
    final notifications = NotificationsController(
      listNotifications: () async => const [],
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => session,
    )..start();
    final connection = ConnectionController();
    addTearDown(jobs.dispose);
    addTearDown(notifications.dispose);
    addTearDown(connection.dispose);
    final routes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        builder: (context, child) => AppBarTrailingHost(
          jobs: jobs,
          connection: connection,
          notifications: notifications,
          onNavigate: routes.add,
          child: child!,
        ),
        home: const Scaffold(
          appBar: QuarkAppBar(label: 'Files', icon: QuarkIcons.folder),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Account'), findsOneWidget, reason: 'no dot');
    expect(find.byKey(const ValueKey('theme_toggle')), findsNothing);

    for (final key in const [
      'account_sheet_jobs',
      'account_sheet_switch_quark',
    ]) {
      await tester.tap(find.byKey(const ValueKey('account_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account_theme_dark')), findsOneWidget);
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }
    expect(routes, ['/system/jobs', '/settings/general']);
  });
}
