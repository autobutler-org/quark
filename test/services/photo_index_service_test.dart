import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/photo_index_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// #3556: the admin-only photo library index routes, as the app reads them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const running = {
    'total': 5000,
    'hashed': 1200,
    'datesRead': 1100,
    'failed': 2,
    'failures': [
      {
        'serial': '',
        'relPath': 'users/ana/photos/broken.jpg',
        'reason': 'undecodable',
      },
      {'serial': 'usb-1', 'relPath': 'Camera/IMG_1.CR2', 'reason': 'odd'},
    ],
    'lastRunAt': null,
    'running': true,
    'paused': false,
  };

  useFakeQuark();

  test('reads the status of a running pass', () async {
    answer(200, running);
    final status = await PhotoIndexService.fetchStatus();
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/photos/index-status');
    expect(status.total, 5000);
    expect(status.hashed, 1200);
    expect(status.datesRead, 1100);
    expect(status.failed, 2);
    expect(status.running, isTrue);
    expect(status.paused, isFalse);
    expect(status.lastRunAt, isNull);
    expect(status.failures.first.serial, isEmpty);
    expect(status.failures.first.relPath, 'users/ana/photos/broken.jpg');
    expect(status.failures.first.reason, PhotoIndexFailureReason.undecodable);
    // A reason this client does not know yet still lists the file.
    expect(status.failures.last.reason, PhotoIndexFailureReason.unknown);
  });

  test('reads every reason class and the last run time', () async {
    answer(200, {
      ...running,
      'failures': [
        for (final reason in [
          'undecodable',
          'missing_converter',
          'too_large',
          'unreadable',
        ])
          {'serial': '', 'relPath': 'a/$reason.jpg', 'reason': reason},
      ],
      'lastRunAt': '2026-10-20T12:00:00Z',
      'running': false,
    });
    final status = await PhotoIndexService.fetchStatus();
    expect(
      [for (final f in status.failures) f.reason],
      [
        PhotoIndexFailureReason.undecodable,
        PhotoIndexFailureReason.missingConverter,
        PhotoIndexFailureReason.tooLarge,
        PhotoIndexFailureReason.unreadable,
      ],
    );
    expect(status.lastRunAt, DateTime.utc(2026, 10, 20, 12));
  });

  test('pause and resume post and read the new status', () async {
    answer(200, {...running, 'paused': true});
    final paused = await PhotoIndexService.pause();
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/v0/photos/index/pause');
    expect(paused.paused, isTrue);

    answer(200, running);
    final resumed = await PhotoIndexService.resume();
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/v0/photos/index/resume');
    expect(resumed.paused, isFalse);
  });

  test('a non-admin is refused with a 403', () async {
    answer(403, {'error': 'admin access required'});
    await expectLater(
      PhotoIndexService.fetchStatus(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });

  test('a body that is not a status is a format error', () async {
    answer(200, ['nope']);
    await expectLater(
      PhotoIndexService.fetchStatus(),
      throwsA(isA<FormatException>()),
    );
  });
}
