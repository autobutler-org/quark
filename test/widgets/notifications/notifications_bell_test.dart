import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/notifications/notifications_bell.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2493: the app bar's bell counts the account's notifications and opens
/// them in a sheet, where tapping one goes to its page.
void main() {
  const bell = ValueKey('notifications_bell');
  final staleAt = DateTime(2026, 9, 1, 10);

  late ValueNotifier<String?> session;
  late List<AppNotification> served;
  late int listCalls;

  NotificationsController build() {
    final controller = NotificationsController(
      listNotifications: () async {
        listCalls++;
        return served;
      },
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => session,
    )..start();
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    session = ValueNotifier('token');
    served = [];
    listCalls = 0;
  });

  Future<void> pumpBell(
    WidgetTester tester,
    NotificationsController controller, {
    ValueChanged<String>? onNavigate,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NotificationsBell(
                controller: controller,
                onNavigate: onNavigate ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('counts, opens the list and goes to the link (${size.width})', (
      tester,
    ) async {
      served = [
        AppNotification(
          type: NotificationType.backupStale,
          link: '/system/storage',
          lastBackupAt: staleAt,
        ),
      ];
      final routes = <String>[];
      await pumpBell(tester, build(), onNavigate: routes.add, size: size);
      expect(find.byTooltip('1 notification'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(bell));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(listCalls, 2, reason: 'opening the list asks again');
      expect(find.text('Your backup is out of date'), findsOneWidget);
      expect(find.textContaining('Sep 1, 2026'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('notification_tile_backup_stale')),
      );
      await tester.pumpAndSettle();
      expect(routes, ['/system/storage']);
      expect(
        find.byKey(const ValueKey('notification_tile_backup_stale')),
        findsNothing,
        reason: 'the sheet closes',
      );
    });

    testWidgets('with none, shows no count and an empty list (${size.width})', (
      tester,
    ) async {
      await pumpBell(tester, build(), size: size);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

      await tester.tap(find.byKey(bell));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("You're all caught up"), findsOneWidget);
    });
  }

  testWidgets('says how many when there are several', (tester) async {
    served = const [
      AppNotification(type: NotificationType.backupDue, link: '/a'),
      AppNotification(type: NotificationType.backupStale, link: '/b'),
    ];
    await pumpBell(tester, build());
    expect(find.byTooltip('2 notifications'), findsOneWidget);
  });

  testWidgets('renders nothing while signed out', (tester) async {
    session.value = null;
    final controller = build();
    await pumpBell(tester, controller);
    expect(find.byKey(bell), findsNothing);

    session.value = 'token';
    await tester.pumpAndSettle();
    expect(find.byKey(bell), findsOneWidget);
  });
}
