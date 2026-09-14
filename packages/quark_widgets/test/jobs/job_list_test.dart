import 'package:flutter/material.dart';
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

void main() {
  testBothViewports('shows a spinner while loading with nothing yet', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const JobList(items: [], isLoading: true), size: size);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No jobs yet'), findsNothing);
  });

  testBothViewports('shows the empty copy when there are no jobs', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const JobList(items: []), size: size);
    expect(find.text('No jobs yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const JobList(items: [], error: 'Host unreachable'),
      size: size,
    );
    expect(find.text('Host unreachable'), findsOneWidget);
    expect(find.text('No jobs yet'), findsNothing);
  });

  testBothViewports('keeps the rows on screen under a refresh error', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const JobList(items: _jobs, isLoading: true, error: 'Host unreachable'),
      size: size,
    );
    expect(find.text('Host unreachable'), findsOneWidget);
    expect(find.byKey(const ValueKey('job_row_3')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  testBothViewports('offers Cancel and Retry only where the item does', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const JobList(items: _jobs), size: size);
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

  testBothViewports('reports the job whose action was tapped', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      JobList(
        items: _jobs,
        onCancel: (id) => events.add('cancel $id'),
        onRetry: (id) => events.add('retry $id'),
      ),
      size: size,
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
}
