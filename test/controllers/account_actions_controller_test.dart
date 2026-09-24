import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/account_actions_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';

/// #1762: deleting an account revokes the session on the Quark, so the app has
/// to take the user somewhere afterwards. Deleting the last account returns the
/// appliance to setup, which is expected — it must land in the setup flow and
/// not on a dead screen.
void main() {
  String? deletedFor;
  ({String password, bool database, bool files, bool devices})? reset;

  AccountActionsController controllerThat({
    Object? throwing,
    String destination = '/login',
    bool filesRetained = false,
  }) {
    return AccountActionsController(
      deleteAccountRequest: ({required String password}) async {
        deletedFor = password;
        if (throwing != null) throw throwing;
        return DeleteAccountResult(filesRetained: filesRetained);
      },
      resetQuarkRequest:
          ({
            required String password,
            required bool database,
            required bool files,
            required bool devices,
          }) async {
            reset = (
              password: password,
              database: database,
              files: files,
              devices: devices,
            );
            if (throwing != null) throw throwing;
            return DeleteAccountResult(filesRetained: filesRetained);
          },
      signedOutDestination: () async => destination,
    );
  }

  setUp(() {
    deletedFor = null;
    reset = null;
  });

  test('deleting an account never reaches the appliance', () async {
    final controller = controllerThat();

    await controller.deleteAccount(password: 'pw');

    expect(deletedFor, 'pw');
    expect(reset, isNull);
  });

  test('resetting passes the selection through', () async {
    final controller = controllerThat();

    await controller.resetQuark(
      selection: const QuarkResetSelection(devices: true),
      password: 'pw',
    );

    expect(reset, (password: 'pw', database: true, files: true, devices: true));
    expect(deletedFor, isNull);
  });

  test('routes to setup when that was the last account', () async {
    final controller = controllerThat(destination: AppRoutes.setup);

    final destination = await controller.deleteAccount(password: 'pw');

    expect(destination, AppRoutes.setup);
    expect(controller.error, isNull);
  });

  test('routes to login when the Quark still has an account', () async {
    final controller = controllerThat(destination: AppRoutes.login);

    expect(await controller.deleteAccount(password: 'pw'), AppRoutes.login);
  });

  test('reports the files the Quark kept', () async {
    final controller = controllerThat(filesRetained: true);

    await controller.deleteAccount(password: 'pw');

    expect(controller.filesRetained, isTrue);
  });

  test('a revoked session routes out instead of raising a 401', () async {
    final controller = controllerThat(
      throwing: const UnauthorizedException(),
      destination: AppRoutes.setup,
    );

    final destination = await controller.deleteAccount(password: 'pw');

    expect(destination, AppRoutes.setup);
    expect(controller.error, isNull);
  });

  test('a wrong password stays put with the Errors copy', () async {
    final controller = controllerThat(
      throwing: const MessageException(Errors.incorrectPassword),
    );

    final destination = await controller.deleteAccount(password: 'nope');

    expect(destination, isNull);
    expect(controller.error, Errors.incorrectPassword);
  });

  // #1909: the Quark refuses with 409 and the service maps it to lastAdmin.
  test(
    'the last admin deleting their account reads the last-admin copy',
    () async {
      final controller = controllerThat(
        throwing: const MessageException(Errors.lastAdmin),
      );

      final destination = await controller.deleteAccount(password: 'pw');

      expect(destination, isNull);
      expect(controller.error, Errors.lastAdmin);
    },
  );

  test('an unexplained failure falls back to the generic sentence', () async {
    final controller = controllerThat(throwing: const ApiException(500));

    await controller.deleteAccount(password: 'pw');

    expect(controller.error, 'Your Quark ran into a problem. Try again.');
  });

  test('a failed reset says what it was trying to do', () async {
    final controller = controllerThat(throwing: const ApiException(404));

    await controller.resetQuark(
      selection: const QuarkResetSelection(),
      password: 'pw',
    );

    expect(
      controller.error,
      "Couldn't reset your Quark — it's no longer there.",
    );
  });

  test('publishes the in-flight state and clears it', () async {
    final controller = controllerThat();
    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.isWorking));

    await controller.deleteAccount(password: 'pw');

    expect(seen, [true, false]);
    expect(controller.isWorking, isFalse);
  });
}
