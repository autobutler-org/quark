import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/upload_session_summary.dart';

void main() {
  test('reads the listing the Quark sends', () {
    final list = UploadSessionList.fromJson({
      'active': [
        {
          'sessionId': 'abc',
          'fileName': 'takeout-001.zip',
          'rootDir': 'Imports',
          'serial': 'USB1',
          'totalSize': 2147483648,
          'offset': 8388608,
          'state': 'uploading',
          'createdAt': '2026-11-04T12:00:00Z',
          'updatedAt': '2026-11-04T12:00:05Z',
          'error': '',
        },
      ],
      'finished': [
        {'sessionId': 'old', 'fileName': 'a.bin', 'state': 'canceled'},
        {'sessionId': 'new', 'fileName': 'b.bin', 'state': 'from-the-future'},
      ],
    });

    final active = list.active.single;
    expect(active.sessionId, 'abc');
    expect(active.totalSize, 2147483648);
    expect(active.offset, 8388608);
    expect(active.state, UploadSessionState.uploading);
    expect(active.updatedAt, DateTime.utc(2026, 11, 4, 12, 0, 5));
    expect(list.finished.map((s) => s.state), [
      UploadSessionState.canceled,
      UploadSessionState.unknown,
    ]);
  });

  test('an empty or malformed body is an empty list', () {
    final list = UploadSessionList.fromJson(const {});
    expect(list.active, isEmpty);
    expect(list.finished, isEmpty);
  });
}
