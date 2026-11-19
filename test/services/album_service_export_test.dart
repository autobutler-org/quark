import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, [Object? body]) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(body == null ? '' : jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  group('startExport', () {
    test('posts the albums and the folder and reads the queued job', () async {
      answer(202, {'jobId': 9, 'deviceSerial': 'usb1', 'relPath': 'Out/Trips'});

      final queued = await AlbumService.startExport(
        albumIds: [1, 2],
        deviceSerial: 'usb1',
        folder: 'Out',
      );

      expect(queued.jobId, 9);
      expect(queued.deviceSerial, 'usb1');
      expect(queued.relPath, 'Out/Trips');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/albums/exports');
      expect(jsonDecode(request.body), {
        'albumIds': [1, 2],
        'library': false,
        'deviceSerial': 'usb1',
        'folder': 'Out',
      });
    });

    test('a library export sends no albums', () async {
      answer(202, {'jobId': 3, 'deviceSerial': '', 'relPath': 'x'});

      await AlbumService.startExport(
        albumIds: [1],
        library: true,
        deviceSerial: '',
        folder: '/',
      );

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['library'], isTrue);
      expect(body['albumIds'], isEmpty);
    });

    for (final status in [400, 403, 404, 500]) {
      test('a $status throws an ApiException', () async {
        answer(status, {'error': 'nope'});

        await expectLater(
          AlbumService.startExport(
            albumIds: [1],
            deviceSerial: '',
            folder: 'Out',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', status),
          ),
        );
      });
    }
  });

  group('exportSummary', () {
    test('reads the failures of a partial export', () async {
      answer(200, {
        'jobId': 9,
        'status': 'failed',
        'deviceSerial': '',
        'relPath': 'Out/Trips',
        'copied': 4,
        'failures': [
          {'name': 'a.jpg', 'path': 'Trips/a.jpg', 'reason': 'missing'},
        ],
        'moreFailures': 0,
      });

      final summary = await AlbumService.exportSummary(9);

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v0/albums/exports/9');
      expect(summary.status, JobStatus.failed);
      expect(summary.failures.single.name, 'a.jpg');
      expect(summary.failures.single.reason, AlbumExportFailureReason.missing);
      expect(summary.isComplete, isFalse);
    });

    test('a 404 throws an ApiException', () async {
      answer(404, {'error': 'no such export'});

      await expectLater(
        AlbumService.exportSummary(9),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });
}
