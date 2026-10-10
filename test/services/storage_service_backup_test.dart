import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

/// #3084: a snapshot backup is a row in the Quark's jobs table, so the storage
/// tab's status poll gets the same answer from whichever instance it reaches.
/// The bodies here are the ones the Quark sends.
void main() {
  void respondWith(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((request) async => http.Response(jsonEncode(body), status));
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('starting a backup returns the job id', () async {
    respondWith(202, {'jobId': '7'});

    expect(
      await StorageService.startSnapshotBackup(targetDeviceSerial: 'USB-1'),
      '7',
    );
  });

  test('a second start for a busy target is a 409', () async {
    respondWith(409, {
      'error': 'backup already running for this device (job 7)',
    });

    await expectLater(
      StorageService.startSnapshotBackup(targetDeviceSerial: 'USB-1'),
      throwsA(isA<Exception>()),
    );
  });

  test('status reads the job the Quark describes', () async {
    respondWith(200, {
      'id': '7',
      'status': 'COPYING',
      'targetDeviceSerial': 'USB-1',
      'progress': 0.5,
      'totalFiles': 4,
      'filesCopied': 2,
      'filesSkipped': 0,
      'totalBytes': 400,
      'bytesCopied': 200,
      'sourceDevices': <Object>[],
    });

    final status = await StorageService.getSnapshotBackupStatus('7');

    expect(status.id, '7');
    expect(status.isRunning, isTrue);
    expect(status.progress, 0.5);
    expect(status.filesCopied, 2);
    expect(status.totalFiles, 4);
    expect(status.bytesCopied, 200);
  });

  test('a backup cut off by a restart reads as failed', () async {
    respondWith(200, {
      'id': '7',
      'status': 'FAILED',
      'errorMsg': 'interrupted by restart',
    });

    final status = await StorageService.getSnapshotBackupStatus('7');

    expect(status.isRunning, isFalse);
    expect(status.isFailed, isTrue);
    expect(status.errorMsg, 'interrupted by restart');
  });

  test('status of a job the Quark does not have is a 404', () async {
    respondWith(404, {'error': 'backup job not found'});

    await expectLater(
      StorageService.getSnapshotBackupStatus('7'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('verify reads the result the Quark sends', () async {
    respondWith(200, {
      'ok': 3,
      'missing': ['a.txt'],
    });

    final result = await StorageService.verifySnapshotBackup(
      deviceSerial: 'USB-1',
    );

    expect(result.ok, 3);
    expect(result.missing, ['a.txt']);
    expect(result.isHealthy, isFalse);
  });
}
