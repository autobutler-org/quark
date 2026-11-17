import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/jobs_service.dart';
import 'package:quark/utils/error_text.dart';

void main() {
  final base = Uri.parse('https://quark.local:8443');

  test('names each kind as its own repeated parameter', () {
    final uri = JobsService.listJobsUri(base, [
      JobKinds.videoTranscode,
      'backup',
    ]);

    expect(
      uri.toString(),
      'https://quark.local:8443/api/v0/jobs?kind=video-transcode&kind=backup',
    );
    expect(uri.queryParametersAll['kind'], ['video-transcode', 'backup']);
  });

  test('refuses to list no kinds, which the Quark rejects', () {
    expect(
      () => JobsService.listJobsUri(base, const []),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('retryJob', () {
    tearDown(() {
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    void answer(int status, String body) {
      resetSharedHttpClient();
      sharedHttpClientFactory = () =>
          MockClient((_) async => http.Response(body, status));
    }

    test('a 422 naming a reason throws a VideoRefusal (#4255)', () async {
      answer(422, '{"error":"job cannot be retried","reason":"damaged"}');
      await expectLater(
        JobsService.retryJob(7),
        throwsA(
          isA<VideoRefusal>().having((e) => e.reason, 'reason', 'damaged'),
        ),
      );
    });

    test('a 422 for a deleted source names no reason', () async {
      answer(
        422,
        '{"error":"job cannot be retried: source not found","reason":""}',
      );
      await expectLater(
        JobsService.retryJob(7),
        throwsA(isA<VideoRefusal>().having((e) => e.reason, 'reason', isNull)),
      );
    });

    test('any other refusal keeps its status', () async {
      answer(409, '{"error":"job is not failed"}');
      await expectLater(
        JobsService.retryJob(7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e is VideoRefusal, 'is VideoRefusal', isFalse),
        ),
      );
    });
  });
}
