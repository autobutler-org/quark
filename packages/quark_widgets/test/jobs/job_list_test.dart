import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The job status list: every state it declares, its actions, and its keys.
const _running = JobItem(
  id: 3,
  name: 'Convert vacation.mkv to MOV',
  status: JobItemStatus.running,
  progress: 0.45,
  attempts: 2,
  elapsed: Duration(seconds: 83),
  isQuickCopy: true,
  canCancel: true,
);
const _pending = JobItem(
  id: 2,
  name: 'Convert party.mov to MP4',
  status: JobItemStatus.pending,
  canCancel: true,
);
const _failed = JobItem(
  id: 1,
  name: 'Convert old.wmv to MP4',
  status: JobItemStatus.failed,
  attempts: 1,
  elapsed: Duration(hours: 1, minutes: 2, seconds: 3),
  canRetry: true,
);
const _completed = JobItem(
  id: 0,
  name: 'Convert birthday.mkv to MP4',
  status: JobItemStatus.completed,
  elapsed: Duration(seconds: 7),
);
const _jobs = [_running, _pending, _failed, _completed];

const _uploading = UploadItem(
  id: 'up1',
  fileName: 'takeout-001.zip',
  destination: 'To Imports on an external drive',
  status: UploadItemStatus.uploading,
  sentBytes: 512 * 1024 * 1024,
  totalBytes: 2 * 1024 * 1024 * 1024,
  bytesPerSecond: 12.5 * 1024 * 1024,
  remaining: Duration(minutes: 2, seconds: 3),
  canCancel: true,
);
const _finishing = UploadItem(
  id: 'up2',
  fileName: 'takeout-002.zip',
  status: UploadItemStatus.finishing,
  sentBytes: 2048,
  totalBytes: 2048,
);
const _stalled = UploadItem(
  id: 'up3',
  fileName: 'takeout-003.zip',
  status: UploadItemStatus.stalled,
  sentBytes: 1536,
  totalBytes: 4096,
  bytesPerSecond: 100,
  canCancel: true,
);
const _uploaded = UploadItem(
  id: 'up4',
  fileName: 'takeout-004.zip',
  status: UploadItemStatus.completed,
  sentBytes: 5 * 1024 * 1024,
  totalBytes: 5 * 1024 * 1024,
);
const _uploads = [_uploading, _finishing, _stalled, _uploaded];

void main() {
  testWidgets('shows a spinner while loading with nothing yet', (tester) async {
    await pumpAt(tester, const JobList(items: [], isLoading: true));
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No jobs yet'), findsNothing);
  });

  testWidgets('renders the error the caller handed it', (tester) async {
    await pumpAt(tester, const JobList(items: [], error: 'Host unreachable'));
    expect(find.text('Host unreachable'), findsOneWidget);
    expect(find.text('No jobs yet'), findsNothing);
  });

  testWidgets('keeps the rows on screen under a refresh error', (tester) async {
    await pumpAt(
      tester,
      const JobList(items: _jobs, isLoading: true, error: 'Host unreachable'),
    );
    expect(find.text('Host unreachable'), findsOneWidget);
    expect(find.byKey(const ValueKey('job_row_3')), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('describes each job and lays out cleanly', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const JobList(items: _jobs), size: size);
    expect(tester.takeException(), isNull);

    expect(find.text('Convert vacation.mkv to MOV'), findsOneWidget);
    expect(
      find.text('Running · 45% · 1:23 · Attempt 2 · Quick copy'),
      findsOneWidget,
    );
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Failed · 1:02:03'), findsOneWidget);
    expect(find.text('Completed · 0:07'), findsOneWidget);
    // Only the running job has a bar.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('offers Cancel and Retry only where the item does', (
    tester,
  ) async {
    await pumpAt(tester, const JobList(items: _jobs));
    for (final job in _jobs) {
      expect(find.byKey(ValueKey('job_row_${job.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('job_cancel_${job.id}')),
        job.canCancel ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(ValueKey('job_retry_${job.id}')),
        job.canRetry ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets('reports the job whose action was tapped', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      JobList(
        items: _jobs,
        onCancel: (id) => events.add('cancel $id'),
        onRetry: (id) => events.add('retry $id'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('job_cancel_3')));
    await tester.tap(find.byKey(const ValueKey('job_cancel_2')));
    await tester.tap(find.byKey(const ValueKey('job_retry_1')));
    await tester.pump();

    expect(events, ['cancel 3', 'cancel 2', 'retry 1']);
  });

  testWidgets('disables an action the caller did not wire', (tester) async {
    await pumpAt(tester, const JobList(items: _jobs));
    final cancel = tester.widget<TextButton>(
      find.byKey(const ValueKey('job_cancel_3')),
    );
    expect(cancel.onPressed, isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: a failed status is drawn in the error token', (
      tester,
    ) async {
      await pumpAt(tester, const JobList(items: _jobs), brightness: brightness);
      expect(tester.takeException(), isNull);
      final status = tester.widget<Text>(find.text('Failed · 1:02:03'));
      expect(status.style?.color, tokens.error);
    });
  }

  testBothViewports('survives a long name and a long list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      JobList(
        items: [
          for (var i = 0; i < 200; i++)
            JobItem(
              id: i,
              name: 'Convert vacation.mkv to MOV ' * 20,
              status: JobItemStatus.running,
              progress: 0.5,
              elapsed: const Duration(seconds: 5),
              isQuickCopy: true,
              canCancel: true,
            ),
        ],
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  /// #2038: the empty state read "Conversions and other long tasks show up
  /// here", which names the category rather than anything a first-time owner
  /// would recognize.
  testWidgets('the empty state names something a household would recognize', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const JobList(items: [], isLoading: false),
      size: narrowViewport,
    );

    expect(find.text('No jobs yet'), findsOneWidget);
    expect(find.textContaining('converting a video'), findsOneWidget);
    expect(find.textContaining('Conversions'), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('describes each upload above the jobs', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const JobList(items: _jobs, uploads: _uploads),
      size: size,
    );
    expect(tester.takeException(), isNull);

    expect(find.text('takeout-001.zip'), findsOneWidget);
    expect(find.text('To Imports on an external drive'), findsOneWidget);
    expect(
      find.text('Uploading · 512 MB of 2.0 GB · 13 MB/s · About 3 min left'),
      findsOneWidget,
    );
    expect(find.text('Finishing · 2.0 KB of 2.0 KB'), findsOneWidget);
    // A stalled upload shows no rate: nothing is moving.
    expect(find.text('Stalled · 1.5 KB of 4.0 KB'), findsOneWidget);
    expect(find.text('Uploaded · 5.0 MB'), findsOneWidget);
    // Three uploads in flight and one running job have bars.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));

    final firstUpload = tester.getTopLeft(
      find.byKey(const ValueKey('upload_row_up1')),
    );
    final firstJob = tester.getTopLeft(find.byKey(const ValueKey('job_row_3')));
    expect(firstUpload.dy, lessThan(firstJob.dy));
  });

  testWidgets('offers Cancel on an upload only where the item does', (
    tester,
  ) async {
    final canceled = <String>[];
    await pumpAt(
      tester,
      JobList(items: const [], uploads: _uploads, onCancelUpload: canceled.add),
    );
    for (final upload in _uploads) {
      expect(
        find.byKey(ValueKey('upload_cancel_${upload.id}')),
        upload.canCancel ? findsOneWidget : findsNothing,
      );
    }
    await tester.tap(find.byKey(const ValueKey('upload_cancel_up3')));
    await tester.pump();
    expect(canceled, ['up3']);
  });

  testWidgets('uploads alone are not the empty state', (tester) async {
    await pumpAt(tester, const JobList(items: [], uploads: [_uploading]));
    expect(find.text('No jobs yet'), findsNothing);
    expect(find.byKey(const ValueKey('upload_row_up1')), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: a stalled upload is drawn in the error token', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const JobList(items: [], uploads: [_stalled]),
        brightness: brightness,
      );
      final status = tester.widget<Text>(
        find.text('Stalled · 1.5 KB of 4.0 KB'),
      );
      expect(status.style?.color, tokens.error);
    });
  }
}
