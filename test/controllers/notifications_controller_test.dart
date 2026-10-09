import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';

const _due = AppNotification(
  type: NotificationType.backupDue,
  link: '/system/storage',
);

/// #2493: the account's notifications and its per-type switches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<FileEvent> events;
  late ValueNotifier<String?> session;
  late List<AppNotification> served;
  late Set<String> storedDisabled;
  late int listCalls;
  Object? listError;
  Object? readError;
  Object? saveError;
  final built = <NotificationsController>[];

  NotificationsController build({
    Future<List<AppNotification>> Function()? listNotifications,
    Future<Set<String>> Function()? readDisabled,
  }) {
    final controller = NotificationsController(
      listNotifications:
          listNotifications ??
          () async {
            listCalls++;
            if (listError != null) throw listError!;
            return served;
          },
      readDisabled:
          readDisabled ??
          () async {
            if (readError != null) throw readError!;
            return {...storedDisabled};
          },
      saveEnabled: (type, enabled) async {
        if (saveError != null) throw saveError!;
        enabled
            ? storedDisabled.remove(type.wire)
            : storedDisabled.add(type.wire);
        return {...storedDisabled};
      },
      events: () => events.stream,
      session: () => session,
    );
    built.add(controller);
    return controller;
  }

  setUp(() {
    events = StreamController<FileEvent>.broadcast();
    session = ValueNotifier(null);
    served = [];
    storedDisabled = {};
    listCalls = 0;
    listError = null;
    readError = null;
    saveError = null;
  });

  tearDown(() async {
    for (final controller in built) {
      controller.dispose();
    }
    built.clear();
    await events.close();
  });

  test('loads on sign-in and forgets everything on sign-out', () async {
    served = [_due];
    storedDisabled = {'backup_stale'};
    session.value = 'token';
    final controller = build()..start();
    expect(controller.isSignedIn, isTrue);
    expect(controller.hasLoaded, isFalse);
    await pumpEventQueue();
    expect(listCalls, 1, reason: 'already signed in at start');
    expect(controller.notifications, [_due]);
    expect(controller.hasLoaded, isTrue);
    await controller.loadPreferences();
    expect(controller.isEnabled(NotificationType.backupStale), isFalse);

    session.value = null;
    expect(controller.isSignedIn, isFalse);
    expect(controller.notifications, isEmpty);
    expect(controller.hasLoaded, isFalse);
    expect(controller.preferencesLoaded, isFalse);
    expect(controller.isEnabled(NotificationType.backupStale), isTrue);

    session.value = 'other';
    await pumpEventQueue();
    expect(listCalls, 2);
    expect(controller.notifications, [_due]);
  });

  test('does not load while signed out', () async {
    final controller = build()..start();
    events.add(const FileEvent(kind: 'backup_completed', path: ''));
    await pumpEventQueue();
    expect(listCalls, 0);
    expect(controller.isSignedIn, isFalse);
  });

  test('fetches again when a backup completes', () async {
    served = [_due];
    session.value = 'token';
    final controller = build()..start();
    await pumpEventQueue();
    expect(controller.notifications, [_due]);

    served = [];
    events.add(const FileEvent(kind: 'backup_completed', path: ''));
    await pumpEventQueue();
    expect(listCalls, 2);
    expect(controller.notifications, isEmpty);

    events.add(const FileEvent(kind: 'upload', path: 'a.txt'));
    await pumpEventQueue();
    expect(listCalls, 2, reason: 'an upload changes no notification');

    for (final kind in ['account_changed', 'resync']) {
      events.add(FileEvent(kind: kind, path: ''));
    }
    await pumpEventQueue();
    expect(listCalls, 4);
  });

  test('fetches again when the app comes back to the foreground', () async {
    session.value = 'token';
    build().start();
    await pumpEventQueue();
    expect(listCalls, 1);

    // The states an app passes through on its way to the background and
    // back; the listener only counts a resume that follows them in order.
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await pumpEventQueue();
    expect(listCalls, 2);
  });

  test('a failed first load carries copy from Errors', () async {
    listError = const ApiException(500);
    final controller = build();
    await controller.load();
    expect(
      controller.error,
      Errors.message(const ApiException(500), 'load your notifications'),
    );
    expect(controller.isLoading, isFalse);
    expect(controller.hasLoaded, isFalse);
  });

  test('a failed refresh keeps the list already shown', () async {
    served = [_due];
    final controller = build();
    await controller.load();
    listError = const ApiException(500);
    await controller.load();
    expect(controller.notifications, [_due]);
    expect(controller.hasLoaded, isTrue);
    expect(controller.error, isNotNull);

    listError = null;
    await controller.load();
    expect(controller.error, isNull);
  });

  test('a slower, older answer is dropped', () async {
    final answers = <Completer<List<AppNotification>>>[];
    final controller = build(
      listNotifications: () {
        final answer = Completer<List<AppNotification>>();
        answers.add(answer);
        return answer.future;
      },
    );
    final first = controller.load();
    final second = controller.load();
    answers[1].complete(const []);
    await second;
    answers[0].complete(const [_due]);
    await first;
    expect(controller.notifications, isEmpty);
    expect(controller.isLoading, isFalse);
  });

  test('an answer for the previous session is dropped', () async {
    final answer = Completer<List<AppNotification>>();
    final preferences = Completer<Set<String>>();
    session.value = 'token';
    final controller = build(
      listNotifications: () => answer.future,
      readDisabled: () => preferences.future,
    )..start();
    final reading = controller.loadPreferences();
    session.value = null;
    answer.complete(const [_due]);
    preferences.complete({'backup_due'});
    await reading;
    await pumpEventQueue();
    expect(controller.notifications, isEmpty);
    expect(controller.preferencesLoaded, isFalse);
    expect(controller.isEnabled(NotificationType.backupDue), isTrue);
  });

  test('turning a type off saves it and fetches the list again', () async {
    served = [_due];
    final controller = build();
    await controller.load();
    await controller.loadPreferences();
    expect(controller.preferencesLoaded, isTrue);
    expect(controller.isEnabled(NotificationType.backupDue), isTrue);

    served = [];
    final saving = controller.setEnabled(NotificationType.backupDue, false);
    expect(controller.isEnabled(NotificationType.backupDue), isFalse);
    expect(controller.isSaving, isTrue, reason: 'flips before the answer');
    await saving;
    expect(controller.isSaving, isFalse);
    expect(storedDisabled, {'backup_due'});
    expect(controller.isEnabled(NotificationType.backupDue), isFalse);
    expect(controller.isEnabled(NotificationType.backupStale), isTrue);
    expect(controller.preferencesError, isNull);
    expect(listCalls, 2);
    expect(controller.notifications, isEmpty);

    await controller.setEnabled(NotificationType.backupDue, true);
    expect(storedDisabled, isEmpty);
    expect(controller.isEnabled(NotificationType.backupDue), isTrue);
  });

  test('a refused save flips the switch back with copy from Errors', () async {
    final controller = build();
    await controller.loadPreferences();
    saveError = const ApiException(400);
    await controller.setEnabled(NotificationType.backupStale, false);
    expect(controller.isEnabled(NotificationType.backupStale), isTrue);
    expect(controller.isSaving, isFalse);
    expect(
      controller.preferencesError,
      Errors.message(const ApiException(400), 'save the setting'),
    );
    expect(listCalls, 0, reason: 'nothing changed, so nothing to fetch');
  });

  test('a failed preferences read carries copy from Errors', () async {
    readError = const ApiException(500);
    final controller = build();
    await controller.loadPreferences();
    expect(controller.preferencesLoaded, isFalse);
    expect(controller.isLoadingPreferences, isFalse);
    expect(
      controller.preferencesError,
      Errors.message(
        const ApiException(500),
        'load your notification settings',
      ),
    );

    readError = null;
    await controller.loadPreferences();
    expect(controller.preferencesLoaded, isTrue);
    expect(controller.preferencesError, isNull);
  });
}
