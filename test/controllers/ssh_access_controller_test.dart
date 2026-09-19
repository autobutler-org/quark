import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/ssh_access_controller.dart';
import 'package:quark/models/ssh_access_status.dart';
import 'package:quark/utils/error_text.dart';

const _key = SshKey(
  type: 'ssh-ed25519',
  fingerprint: 'SHA256:abc',
  comment: 'me@laptop',
);

void main() {
  test('loads the status, and says why when SSH is unavailable', () async {
    final controller = SshAccessController(
      getStatus: () async => const SshAccessStatus(
        available: false,
        reason: 'helper_missing',
        enabled: false,
        keys: [],
      ),
    );
    await controller.load();
    expect(
      controller.unavailableReason,
      Errors.sshUnavailable('helper_missing'),
    );
    expect(controller.unavailableReason, contains('sudo quark install'));
    expect(controller.error, isNull);
  });

  test('a change reloads the status; a password change does not', () async {
    final calls = <String>[];
    var enabled = false;
    final controller = SshAccessController(
      getStatus: () async {
        calls.add('status');
        return SshAccessStatus(
          available: true,
          enabled: enabled,
          keys: const [_key],
        );
      },
      setEnabled: (on) async {
        calls.add('enabled $on');
        enabled = on;
      },
      addKey: (key) async => calls.add('add $key'),
      removeKey: (fingerprint) async => calls.add('remove $fingerprint'),
      setPassword: (password) async => calls.add('set $password'),
      clearPassword: () async => calls.add('clear'),
    );

    expect(await controller.setEnabled(true), isTrue);
    expect(controller.status?.enabled, isTrue);
    expect(await controller.addKey('ssh-ed25519 AAAA'), isTrue);
    expect(await controller.removeKey('SHA256:abc'), isTrue);
    expect(await controller.setPassword('long enough password'), isTrue);
    expect(await controller.clearPassword(), isTrue);
    expect(calls, [
      'enabled true',
      'status',
      'add ssh-ed25519 AAAA',
      'status',
      'remove SHA256:abc',
      'status',
      'set long enough password',
      'clear',
    ]);
    expect(controller.isWorking, isFalse);
  });

  test('a failure becomes copy from Errors, never the exception', () async {
    final controller = SshAccessController(
      addKey: (_) async =>
          throw const MessageException('that key is already allowed'),
      setEnabled: (_) async =>
          throw const ApiException(500, 'ssh-access enable'),
    );
    expect(await controller.addKey('ssh-ed25519 AAAA'), isFalse);
    expect(controller.error, 'That key is already allowed.');
    expect(await controller.setEnabled(true), isFalse);
    expect(
      controller.error,
      Errors.message(const ApiException(500), 'turn on SSH access'),
    );
    expect(controller.error, isNot(contains('ssh-access')));
  });
}
