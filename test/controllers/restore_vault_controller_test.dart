import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restore_vault_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

const _missingAccount =
    'the backup has a vault for an account this Quark does not have; add an '
    'account with the same username, letter for letter, and restore again '
    '(carol, dave)';

const _keyExists =
    'an account the backup has a vault for already has a vault on this Quark, '
    'and a restore never replaces one; that account can delete its empty '
    'vault, then restore again (carol)';

/// The sentence the Storage tab shows after a vault restore, and the refusals
/// the Quark answers with.
void main() {
  test('reports the counts and who unlocks with the backup password', () async {
    final calls = <(String, String)>[];
    final controller = RestoreVaultController(
      restoreVault:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async {
            calls.add((deviceSerial, password));
            return const VaultRestoreResult(
              accounts: 2,
              items: 5,
              backupPasswordAccounts: ['alice', 'bob'],
            );
          },
    );
    addTearDown(controller.dispose);

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(calls, [('USB2', 'secret')]);
    expect(controller.error, isNull);
    expect(controller.result?.accounts, 2);
    expect(controller.result?.items, 5);
    expect(
      controller.summary,
      'Restored 2 vaults and 5 entries. alice and bob unlock with the '
      'password they had when the backup was taken.',
    );

    final one = RestoreVaultController(
      restoreVault:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async => const VaultRestoreResult(
            accounts: 1,
            items: 1,
            backupPasswordAccounts: ['alice'],
          ),
    );
    addTearDown(one.dispose);
    await one.restore(deviceSerial: 'USB2', password: 'secret');
    expect(
      one.summary,
      'Restored 1 vault and 1 entry. alice unlocks with the password they '
      'had when the backup was taken.',
    );
  });

  test('a vault that already has items is that sentence', () async {
    final controller = _refusing(
      const MessageException('a vault already has items'),
    );

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(controller.result, isNull);
    expect(
      Errors.message(controller.error, 'restore the vaults'),
      'A vault already has items.',
    );
  });

  test('a missing account is named, capitalized, and closed', () async {
    final controller = _refusing(const MessageException(_missingAccount));

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      Errors.message(controller.error, 'restore the vaults'),
      'The backup has a vault for an account this Quark does not have; add '
      'an account with the same username, letter for letter, and restore '
      'again (carol, dave).',
    );
  });

  test('an account that already has a vault key is named', () async {
    final controller = _refusing(const MessageException(_keyExists));

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      Errors.message(controller.error, 'restore the vaults'),
      'An account the backup has a vault for already has a vault on this '
      'Quark, and a restore never replaces one; that account can delete its '
      'empty vault, then restore again (carol).',
    );
  });

  test('a missing drive is the 404 sentence', () async {
    final controller = _refusing(const ApiException(404));

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      Errors.message(controller.error, 'restore the vaults'),
      "Couldn't restore the vaults — it's no longer there.",
    );
  });

  test('a drive with no vault backup shows the Quark\'s sentence', () async {
    final controller = _refusing(
      const MessageException('the drive holds no vault backup'),
    );

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      Errors.message(controller.error, 'restore the vaults'),
      'The drive holds no vault backup.',
    );
  });
}

RestoreVaultController _refusing(Object error) {
  final controller = RestoreVaultController(
    restoreVault:
        ({
          required String deviceSerial,
          required String password,
          String? run,
        }) => Future<VaultRestoreResult>.error(error),
  );
  addTearDown(controller.dispose);
  return controller;
}
