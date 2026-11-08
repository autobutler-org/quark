import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

/// #4032 and #4044: a backup drive's runs are listed and deleted, and a
/// restore or verify names the run it reads. The bodies here are the ones
/// the Quark sends.
void main() {
  final requests = <http.Request>[];

  void respondWith(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('lists the runs newest first with their drives', () async {
    respondWith(200, {
      'runs': [
        {
          'folder': '2026-11-02 09.00',
          'completedAt': '2026-11-02T09:12:00Z',
          'sizeBytes': 1288490188,
          'drives': [
            {'folder': 'Built-in storage', 'serial': '', 'name': ''},
            {
              'folder': 'Photos (USB 90C82C65)',
              'serial': '90C82C65AB',
              'name': 'Photos',
            },
          ],
        },
        {'folder': '2026-10-26 09.00'},
      ],
    });

    final runs = await StorageService.listBackupRuns('USB2');

    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.path,
      '/api/v0/storage/devices/snapshot-backup/runs',
    );
    expect(requests.single.url.queryParameters, {'deviceSerial': 'USB2'});
    expect(runs.map((r) => r.folder), ['2026-11-02 09.00', '2026-10-26 09.00']);
    expect(runs.first.completedAt, DateTime.utc(2026, 11, 2, 9, 12));
    expect(runs.first.sizeBytes, 1288490188);
    expect(runs.first.drives.last, (
      folder: 'Photos (USB 90C82C65)',
      serial: '90C82C65AB',
      name: 'Photos',
    ));
    expect(runs.last.completedAt, isNull);
    expect(runs.last.drives, isEmpty);
  });

  test('a drive with no runs lists none', () async {
    respondWith(200, {'runs': <Object>[]});

    expect(await StorageService.listBackupRuns(''), isEmpty);
  });

  test('deleting sends the drive and the run', () async {
    respondWith(200, {
      'run': {'folder': '2026-10-26 09.00'},
    });

    await StorageService.deleteBackupRun(
      deviceSerial: 'USB2',
      run: '2026-10-26 09.00',
    );

    expect(requests.single.method, 'DELETE');
    expect(jsonDecode(requests.single.body), {
      'deviceSerial': 'USB2',
      'run': '2026-10-26 09.00',
    });
  });

  test('a busy drive is a 409 Errors can word', () async {
    respondWith(409, {
      'error':
          'the drive is busy; delete the backup once it finishes: backup '
          'job 7 is writing to it',
    });

    await expectLater(
      StorageService.deleteBackupRun(deviceSerial: 'USB2', run: 'x'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('restore and verify send the picked run and read it back', () async {
    respondWith(202, {
      'jobId': '9',
      'run': '2026-10-26 09.00',
      'folders': <Object>[],
    });
    final files = await StorageService.restoreSnapshotFiles(
      deviceSerial: 'USB2',
      missingToBuiltIn: false,
      run: '2026-10-26 09.00',
    );
    expect(jsonDecode(requests.last.body)['run'], '2026-10-26 09.00');
    expect(files.run, '2026-10-26 09.00');

    respondWith(200, {'ok': 3, 'run': '2026-11-02 09.00'});
    final verify = await StorageService.verifySnapshotBackup(
      deviceSerial: 'USB2',
    );
    expect((jsonDecode(requests.last.body) as Map).containsKey('run'), isFalse);
    expect(verify.run, '2026-11-02 09.00');
  });

  test('no backup yet is a 404 Errors can word', () async {
    respondWith(404, {'error': 'the drive holds no snapshot of any device'});

    await expectLater(
      StorageService.restoreSnapshotFiles(
        deviceSerial: 'USB2',
        missingToBuiltIn: false,
      ),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('a picked run that is gone keeps the Quark\'s words', () async {
    respondWith(404, {
      'error': 'the drive holds no complete backup of that name',
    });

    await expectLater(
      StorageService.restoreSnapshotFiles(
        deviceSerial: 'USB2',
        missingToBuiltIn: false,
        run: 'gone',
      ),
      throwsA(isA<MessageException>()),
    );
  });
}
