import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/trash_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) {
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

  test('lists a device trash and stamps each item with the device', () async {
    answer(200, {
      'retentionDays': 30,
      'items': [
        {
          'trashName': '20260901T120000Z_ab12_report.pdf',
          'name': 'report.pdf',
          'originalPath': 'Documents/report.pdf',
          'isDir': false,
          'size': 2048,
          'trashedAt': '2026-09-01T12:00:00Z',
          'expiresAt': '2026-10-01T12:00:00Z',
        },
      ],
    });

    final listing = await TrashService.listTrash('USB1', deviceName: 'Drive');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/trash');
    expect(requests.single.url.queryParameters, {'serial': 'USB1'});
    expect(listing.retentionDays, 30);
    final item = listing.items.single;
    expect(item.trashName, '20260901T120000Z_ab12_report.pdf');
    expect(item.name, 'report.pdf');
    expect(item.originalFolder, '/Documents');
    expect(item.size, 2048);
    expect(item.expiresAt, DateTime.utc(2026, 10, 1, 12));
    expect(item.deviceSerial, 'USB1');
    expect(item.deviceName, 'Drive');
  });

  test('lists a trashed folder by name and path', () async {
    answer(200, {
      'items': [
        {
          'name': 'one.jpg',
          'path': '2024/one.jpg',
          'isDir': false,
          'size': 12,
          'modifiedAt': '2026-08-01T00:00:00Z',
        },
      ],
      'originalPath': 'Pictures/album/2024',
      'expiresAt': '2026-10-01T12:00:00Z',
    });

    final contents = await TrashService.listContents('USB1', 'x_album', '2024');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/trash/contents');
    expect(requests.single.url.queryParameters, {
      'serial': 'USB1',
      'trashName': 'x_album',
      'path': '2024',
    });
    expect(contents.originalPath, 'Pictures/album/2024');
    expect(contents.expiresAt, DateTime.utc(2026, 10, 1, 12));
    final item = contents.items.single;
    expect(item.name, 'one.jpg');
    expect(item.path, '2024/one.jpg');
    expect(item.isDir, isFalse);
    expect(item.size, 12);
  });

  test('restore posts the items and returns the restored paths', () async {
    answer(200, {
      'restoredPaths': ['Documents/report.pdf', 'Pictures/album/2024'],
    });

    final paths = await TrashService.restore('', [
      const TrashRef('a_report.pdf'),
      const TrashRef('x_album', '2024'),
    ]);

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/trash/restore');
    expect(jsonDecode(requests.single.body), {
      'serial': '',
      'items': [
        {'trashName': 'a_report.pdf', 'path': ''},
        {'trashName': 'x_album', 'path': '2024'},
      ],
    });
    expect(paths, ['Documents/report.pdf', 'Pictures/album/2024']);
  });

  test('a refused restore throws the status, not the server text', () async {
    answer(409, {'error': 'cannot restore: Documents/report.pdf'});

    await expectLater(
      TrashService.restore('', [const TrashRef('a_report.pdf')]),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('delete and empty return how many items went', () async {
    answer(200, {'deleted': 2});

    expect(
      await TrashService.deletePermanently('USB1', [
        const TrashRef('a'),
        const TrashRef('b', 'c.txt'),
      ]),
      2,
    );
    expect(await TrashService.empty('USB1'), 2);

    expect(requests.map((r) => r.url.path), [
      '/api/v0/trash/delete',
      '/api/v0/trash/empty',
    ]);
    expect(jsonDecode(requests.first.body), {
      'serial': 'USB1',
      'items': [
        {'trashName': 'a', 'path': ''},
        {'trashName': 'b', 'path': 'c.txt'},
      ],
    });
    expect(jsonDecode(requests.last.body), {'serial': 'USB1'});
  });
}
