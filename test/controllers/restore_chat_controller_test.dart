import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restore_chat_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';
import 'package:quark/utils/error_text.dart';

/// The sentence the Storage tab shows after a chat restore, and the refusals
/// the Quark answers with (#2428).
void main() {
  test('reports the counts and the backup, and sends the run', () async {
    final calls = <(String, String, String?)>[];
    final controller = RestoreChatController(
      restoreChat:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async {
            calls.add((deviceSerial, password, run));
            return const ChatRestoreResult(
              channels: 3,
              messages: 12,
              run: '2026-11-02 09.00',
            );
          },
    );
    addTearDown(controller.dispose);

    await controller.restore(
      deviceSerial: 'USB2',
      password: 'secret',
      run: '2026-11-02 09.00',
    );

    expect(calls, [('USB2', 'secret', '2026-11-02 09.00')]);
    expect(controller.error, isNull);
    expect(controller.result?.channels, 3);
    expect(
      controller.summary,
      'Restored 3 channels and 12 messages, backed up '
      '${backupRunLabel('2026-11-02 09.00')}.',
    );
  });

  test('names the usernames no account matched', () async {
    final controller = RestoreChatController(
      restoreChat:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async => const ChatRestoreResult(
            channels: 1,
            messages: 1,
            unmatchedUsers: ['carol', 'dave'],
          ),
    );
    addTearDown(controller.dispose);

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      controller.summary,
      'Restored 1 channel and 1 message. No account here matched these '
      'usernames, so their messages show no author: carol, dave.',
    );
  });

  test('a chat that is not empty is that sentence', () async {
    final controller = _refusing(
      const MessageException('chat already has channels or messages'),
    );

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(controller.result, isNull);
    expect(controller.summary, isNull);
    expect(
      Errors.message(controller.error, 'restore the chat'),
      'Chat already has channels or messages.',
    );
  });

  test('a drive without the backup role shows the Quark\'s sentence', () async {
    final controller = _refusing(
      const MessageException(
        'chat is restored only from a drive with the snapshot-backup role',
      ),
    );

    await controller.restore(deviceSerial: 'USB2', password: 'secret');

    expect(
      Errors.message(controller.error, 'restore the chat'),
      'Chat is restored only from a drive with the snapshot-backup role.',
    );
  });
}

RestoreChatController _refusing(Object error) {
  final controller = RestoreChatController(
    restoreChat:
        ({
          required String deviceSerial,
          required String password,
          String? run,
        }) => Future<ChatRestoreResult>.error(error),
  );
  addTearDown(controller.dispose);
  return controller;
}
