import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/job.dart';
import 'package:quark/services/jobs_service.dart';

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
}
