import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restore_files_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

/// The sentence the Storage tab shows after starting a file restore (#4009),
/// and the refusals the Quark answers with.
void main() {
  test('says where the files go and which drives are not attached', () async {
    final calls = <(String, bool)>[];
    final controller = RestoreFilesController(
      restoreFiles:
          ({
            required String deviceSerial,
            required bool missingToBuiltIn,
            String? run,
          }) async {
            calls.add((deviceSerial, missingToBuiltIn));
            return FilesRestoreResult.fromJson(const {
              'jobId': '7',
              'folders': [
                {'folder': 'internal', 'targetSerial': '', 'toBuiltIn': false},
                {
                  'folder': 'Photos_ABC',
                  'targetSerial': 'ABC',
                  'toBuiltIn': false,
                },
              ],
              'missing': ['Old_GONE'],
            });
          },
    );
    addTearDown(controller.dispose);

    await controller.restore(deviceSerial: 'USB2', missingToBuiltIn: false);

    expect(calls, [('USB2', false)]);
    expect(controller.error, isNull);
    expect(controller.result?.jobId, '7');
    expect(
      controller.summary,
      'Restoring files from 2 drives. Old_GONE stays on the backup drive: '
      'its drive is not attached.',
    );
  });

  test('names the folders that go onto built-in storage', () {
    final result = FilesRestoreResult.fromJson(const {
      'jobId': '8',
      'folders': [
        {'folder': 'Old_GONE', 'targetSerial': '', 'toBuiltIn': true},
      ],
    });
    expect(result.missing, isEmpty);
    expect(
      restoreFilesSummary(result),
      'Restoring files from 1 drive. Old_GONE goes to built-in storage.',
    );
  });

  test('names the backup it restores from', () {
    final result = FilesRestoreResult.fromJson(const {
      'jobId': '9',
      'run': '2026-11-02 09.00',
      'folders': [
        {'folder': 'Built-in storage', 'targetSerial': '', 'toBuiltIn': false},
      ],
    });
    expect(
      restoreFilesSummary(result),
      'Restoring files from 1 drive, backed up Nov 2, 09.00.',
    );
  });

  test('keeps a refusal for the page to word', () async {
    final controller = RestoreFilesController(
      restoreFiles:
          ({
            required String deviceSerial,
            required bool missingToBuiltIn,
            String? run,
          }) => throw const MessageException('the drive holds no snapshot'),
    );
    addTearDown(controller.dispose);

    await controller.restore(deviceSerial: 'USB2', missingToBuiltIn: true);

    expect(controller.result, isNull);
    expect(controller.summary, isNull);
    expect(
      Errors.message(controller.error!, 'restore the files'),
      'The drive holds no snapshot.',
    );
  });
}
