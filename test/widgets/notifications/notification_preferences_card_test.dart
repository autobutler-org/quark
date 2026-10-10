import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/notifications/notification_preferences_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2493: the Settings switches that turn each notification type on or off.
void main() {
  const dueToggle = ValueKey('notification_toggle_backup_due');
  const staleToggle = ValueKey('notification_toggle_backup_stale');
  const retry = ValueKey('notification_preferences_retry');

  late Set<String> stored;
  Object? readError;
  Object? saveError;

  NotificationsController build({
    Future<Set<String>> Function()? read,
    Future<Set<String>> Function(NotificationType type, bool enabled)? save,
  }) {
    final controller = NotificationsController(
      listNotifications: () async => const [],
      readDisabled:
          read ??
          () async {
            if (readError != null) throw readError!;
            return {...stored};
          },
      saveEnabled:
          save ??
          (type, enabled) async {
            if (saveError != null) throw saveError!;
            enabled ? stored.remove(type.wire) : stored.add(type.wire);
            return {...stored};
          },
      events: () => const Stream<FileEvent>.empty(),
      session: () => ValueNotifier('token'),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    stored = {};
    readError = null;
    saveError = null;
  });

  Future<void> pumpCard(
    WidgetTester tester,
    NotificationsController controller, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [NotificationPreferencesCard(controller: controller)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isOn(WidgetTester tester, Key key) =>
      tester.widget<SwitchListTile>(find.byKey(key)).value;

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('shows a switch per type and saves a flip (${size.width})', (
      tester,
    ) async {
      stored = {'backup_stale'};
      await pumpCard(tester, build(), size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Notifications'), findsOneWidget);
      expect(
        find.byType(SwitchListTile),
        findsNWidgets(NotificationType.values.length),
      );
      expect(isOn(tester, dueToggle), isTrue);
      expect(isOn(tester, staleToggle), isFalse);

      await tester.tap(find.byKey(dueToggle));
      await tester.pumpAndSettle();
      expect(stored, {'backup_stale', 'backup_due'});
      expect(isOn(tester, dueToggle), isFalse);

      await tester.tap(find.byKey(staleToggle));
      await tester.pumpAndSettle();
      expect(stored, {'backup_due'});
      expect(isOn(tester, staleToggle), isTrue);
    });

    testWidgets('a refused save flips back and says why (${size.width})', (
      tester,
    ) async {
      saveError = const ApiException(500);
      await pumpCard(tester, build(), size: size);
      await tester.tap(find.byKey(dueToggle));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(isOn(tester, dueToggle), isTrue);
      expect(
        find.text(Errors.message(const ApiException(500), 'save the setting')),
        findsOneWidget,
      );
      expect(
        find.byKey(retry),
        findsNothing,
        reason: 'the switch is the retry',
      );
    });

    testWidgets('a failed read can be tried again (${size.width})', (
      tester,
    ) async {
      readError = const ApiException(500);
      await pumpCard(tester, build(), size: size);
      expect(tester.takeException(), isNull);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.text(
          Errors.message(
            const ApiException(500),
            'load your notification settings',
          ),
        ),
        findsOneWidget,
      );

      readError = null;
      await tester.tap(find.byKey(retry));
      await tester.pumpAndSettle();
      expect(find.byKey(retry), findsNothing);
      expect(isOn(tester, dueToggle), isTrue);
    });
  }

  testWidgets('shows a loader until the choices arrive', (tester) async {
    final answer = Completer<Set<String>>();
    final controller = build(read: () => answer.future);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: NotificationPreferencesCard(controller: controller),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);

    answer.complete({'backup_due'});
    await tester.pumpAndSettle();
    expect(find.byType(QuarkLoader), findsNothing);
    expect(isOn(tester, dueToggle), isFalse);
  });

  testWidgets('the switches are disabled while a save is in flight', (
    tester,
  ) async {
    final answer = Completer<Set<String>>();
    await pumpCard(tester, build(save: (_, _) => answer.future));
    await tester.tap(find.byKey(dueToggle));
    await tester.pump();
    expect(isOn(tester, dueToggle), isFalse, reason: 'flips at once');
    expect(
      tester.widget<SwitchListTile>(find.byKey(staleToggle)).onChanged,
      isNull,
    );
    answer.complete({'backup_due'});
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byKey(staleToggle)).onChanged,
      isNotNull,
    );
  });
}
