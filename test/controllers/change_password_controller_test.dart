import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/change_password_controller.dart';
import 'package:quark/utils/error_text.dart';

/// #3022: the change-password dialog stays up while the change runs, so the
/// controller has to say when it is working, whether it went through, and
/// why not in words from [Errors].
void main() {
  final sent = <({String current, String next})>[];

  setUp(sent.clear);

  /// A controller whose request records what it was handed, then throws
  /// [throwing] or waits on [until].
  ChangePasswordController controllerThat({
    Object? throwing,
    Future<void>? until,
  }) {
    final controller = ChangePasswordController(
      changePasswordRequest:
          ({
            required String currentPassword,
            required String newPassword,
          }) async {
            sent.add((current: currentPassword, next: newPassword));
            if (until != null) await until;
            if (throwing != null) throw throwing;
          },
    );
    return controller;
  }

  Future<bool> change(ChangePasswordController controller) => controller
      .changePassword(currentPassword: 'old-password', newPassword: 'new-one');

  test(
    'a change that goes through answers true and says it was working',
    () async {
      final controller = controllerThat();
      addTearDown(controller.dispose);
      final working = <bool>[];
      controller.addListener(() => working.add(controller.isWorking));

      expect(await change(controller), isTrue);

      expect(sent, [(current: 'old-password', next: 'new-one')]);
      expect(working, [true, false]);
      expect(controller.isWorking, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('a wrong current password answers false with the copy for it', () async {
    final controller = controllerThat(
      throwing: const MessageException(Errors.wrongCurrentPassword),
    );
    addTearDown(controller.dispose);

    expect(await change(controller), isFalse);

    expect(controller.error, Errors.wrongCurrentPassword);
    expect(controller.isWorking, isFalse);
  });

  test(
    'a failure nobody wrote copy for reads as the generic sentence',
    () async {
      final controller = controllerThat(
        throwing: Exception('SocketException: errno 111'),
      );
      addTearDown(controller.dispose);

      expect(await change(controller), isFalse);

      expect(controller.error, Errors.couldNot('change your password'));
    },
  );

  test('a rate-limited change says to wait', () async {
    final controller = controllerThat(throwing: const ApiException(429));
    addTearDown(controller.dispose);

    expect(await change(controller), isFalse);

    expect(controller.error, 'Too many requests. Wait a moment and try again.');
  });

  test('the next attempt clears the last failure', () async {
    var fail = true;
    final controller = ChangePasswordController(
      changePasswordRequest:
          ({
            required String currentPassword,
            required String newPassword,
          }) async {
            if (fail) throw const ApiException(429);
          },
    );
    addTearDown(controller.dispose);

    expect(await change(controller), isFalse);
    expect(controller.error, isNotNull);
    fail = false;

    expect(await change(controller), isTrue);
    expect(controller.error, isNull);
  });

  test('a second change while one is in flight sends nothing', () async {
    final gate = Completer<void>();
    final controller = controllerThat(until: gate.future);
    addTearDown(controller.dispose);

    final first = change(controller);
    expect(controller.isWorking, isTrue);
    expect(await change(controller), isFalse);
    // The refused call must not end the first one's working state.
    expect(controller.isWorking, isTrue);
    gate.complete();

    expect(await first, isTrue);
    expect(sent, hasLength(1));
    expect(controller.isWorking, isFalse);
  });

  test('disposing mid-flight does not notify a dead controller', () async {
    final gate = Completer<void>();
    final controller = controllerThat(until: gate.future);

    final flight = change(controller);
    controller.dispose();
    gate.complete();

    expect(await flight, isTrue);
  });

  test('a change that goes through deletes the vault key cached behind '
      'biometrics, and a failed one keeps it (#3595)', () async {
    var wipes = 0;
    var fail = false;
    final controller = ChangePasswordController(
      changePasswordRequest:
          ({
            required String currentPassword,
            required String newPassword,
          }) async {
            if (fail) throw const ApiException(403);
          },
      onPasswordChanged: () async => wipes++,
    );
    addTearDown(controller.dispose);

    fail = true;
    expect(await change(controller), isFalse);
    expect(wipes, 0);

    fail = false;
    expect(await change(controller), isTrue);
    expect(wipes, 1);
  });
}
