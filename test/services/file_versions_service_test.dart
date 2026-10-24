import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/file_versions_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// The version history API client (#2992): the routes it calls, what it
/// reads from them, and that a refusal surfaces as a status, not Go's text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  const named = {
    'id': 'v2',
    'createdAt': '2026-10-10T09:30:00Z',
    'size': 1536,
    'sha256': 'abc',
    'kind': 'named',
    'label': 'Final draft',
    'authorId': 7,
  };
  const auto = {
    'id': 'v1',
    'createdAt': '2026-10-09T08:00:00Z',
    'size': 900,
    'sha256': 'def',
    'kind': 'auto',
  };

  test('lists the versions of a path, newest first as sent', () async {
    answer(200, {
      'versions': [named, auto],
    });

    final versions = await FileVersionsService.list('Docs/notes.md');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/versions');
    expect(requests.single.url.queryParameters, {'path': 'Docs/notes.md'});
    expect(versions.map((v) => v.id), ['v2', 'v1']);
    expect(versions.first.createdAt, DateTime.utc(2026, 10, 10, 9, 30));
    expect(versions.first.size, 1536);
    expect(versions.first.sha256, 'abc');
    expect(versions.first.isNamed, isTrue);
    expect(versions.first.label, 'Final draft');
    expect(versions.first.authorId, 7);
    expect(versions.last.isNamed, isFalse);
    expect(versions.last.label, '');
    expect(versions.last.authorId, 0, reason: 'absent means the system');
  });

  test('reads an empty history', () async {
    answer(200, {'versions': <Object>[]});

    expect(await FileVersionsService.list('a.txt'), isEmpty);
  });

  test('fetches the bytes of one version', () async {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response.bytes([1, 2, 3], 200);
    });

    final bytes = await FileVersionsService.content('Docs/notes.md', 'v1');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/versions/v1/content');
    expect(requests.single.url.queryParameters, {'path': 'Docs/notes.md'});
    expect(bytes, [1, 2, 3]);
  });

  test('restores a version and returns the backup it took first', () async {
    answer(200, {
      'restored': auto,
      'backup': {...auto, 'id': 'v3', 'label': 'Before restore'},
    });

    final backup = await FileVersionsService.restore('Docs/notes.md', 'v1');

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/versions/v1/restore');
    expect(requests.single.url.queryParameters, {'path': 'Docs/notes.md'});
    expect(backup.id, 'v3');
    expect(backup.label, 'Before restore');
  });

  for (final (name, call) in <(String, Future<Object?> Function())>[
    ('list', () => FileVersionsService.list('a.txt')),
    ('content', () => FileVersionsService.content('a.txt', 'v1')),
    ('restore', () => FileVersionsService.restore('a.txt', 'v1')),
  ]) {
    test('$name throws the status of a refusal, not its text', () async {
      answer(403, {'error': 'open /srv/files/a.txt: read-only file system'});

      await expectLater(
        call(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  }
}
