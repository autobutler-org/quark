import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2493: the app-wide scope puts the notifications bell in every page's
/// bar, and the bell opens a route through the root's `onNavigate`.
void main() {
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('every bar gets the notifications bell (${size.width})', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
            appBar: QuarkAppBar(
              label: 'Files',
              icon: QuarkIcons.folder_outlined,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('1 notification'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notifications_bell')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('notification_tile_backup_due')),
      );
      await tester.pumpAndSettle();
      expect(routes, ['/system/storage']);
    });
  }
}
