import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/notifications/notifications_list.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _due = AppNotification(
  type: NotificationType.backupDue,
  link: '/system/storage',
);

/// #2493: the notification list's loading, failed, empty and filled states.
void main() {
  const dueTile = ValueKey('notification_tile_backup_due');
  const retry = ValueKey('notifications_retry');

  NotificationsController build(
    Future<List<AppNotification>> Function() listNotifications,
  ) {
    final controller = NotificationsController(
      listNotifications: listNotifications,
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => ValueNotifier('token'),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> pumpList(
    WidgetTester tester,
    NotificationsController controller, {
    ValueChanged<AppNotification>? onOpen,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          // The sheet scrolls its content, so the list is laid out with no
          // height limit, as here.
          body: SingleChildScrollView(
            child: NotificationsList(
              controller: controller,
              onOpen: onOpen ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('lists each notification and reports a tap (${size.width})', (
      tester,
    ) async {
      final controller = build(
        () async => [
          _due,
          AppNotification(
            type: NotificationType.backupStale,
            link: '/system/storage',
            lastBackupAt: DateTime(2026, 9, 1, 10),
          ),
        ],
      );
      await controller.load();
      final opened = <AppNotification>[];
      await pumpList(tester, controller, onOpen: opened.add, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Back up this Quark'), findsOneWidget);
      expect(find.textContaining('has never been backed up'), findsOneWidget);
      expect(find.text('Your backup is out of date'), findsOneWidget);
      expect(find.textContaining('Sep 1, 2026'), findsOneWidget);

      await tester.tap(find.byKey(dueTile));
      expect(opened, [_due]);
    });

    testWidgets('a failed first load can be tried again (${size.width})', (
      tester,
    ) async {
      var fails = true;
      final controller = build(() async {
        if (fails) throw const ApiException(500);
        return const [_due];
      });
      await controller.load();
      await pumpList(tester, controller, size: size);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          Errors.message(const ApiException(500), 'load your notifications'),
        ),
        findsOneWidget,
      );

      fails = false;
      await tester.tap(find.byKey(retry));
      await tester.pumpAndSettle();
      expect(find.byKey(retry), findsNothing);
      expect(find.byKey(dueTile), findsOneWidget);
    });

    testWidgets('an empty list says so (${size.width})', (tester) async {
      final controller = build(() async => const []);
      await controller.load();
      await pumpList(tester, controller, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text("You're all caught up"), findsOneWidget);
    });
  }

  testWidgets('shows a loader until the first answer only', (tester) async {
    final answers = <Completer<List<AppNotification>>>[];
    final controller = build(() {
      final answer = Completer<List<AppNotification>>();
      answers.add(answer);
      return answer.future;
    });
    unawaited(controller.load());
    await pumpList(tester, controller);
    expect(find.byType(QuarkLoader), findsOneWidget);

    answers.single.complete(const [_due]);
    await tester.pump();
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byKey(dueTile), findsOneWidget);

    unawaited(controller.load());
    await tester.pump();
    expect(controller.isLoading, isTrue);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byKey(dueTile), findsOneWidget, reason: 'rows stay up');
    answers.last.complete(const [_due]);
    await tester.pump();
  });

  testWidgets('a stale backup with no date still reads as a sentence', (
    tester,
  ) async {
    final controller = build(
      () async => const [
        AppNotification(type: NotificationType.backupStale, link: '/x'),
      ],
    );
    await controller.load();
    await pumpList(tester, controller);
    expect(find.textContaining('The last backup is getting old'), findsOne);
  });
}
