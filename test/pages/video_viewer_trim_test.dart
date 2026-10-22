import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/models/job.dart';
import 'package:quark/models/playback_position.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

/// #3426: Save Clip queues a trim job. While it runs the app bar shows it busy
/// with a Cancel that stops the job, and the job's finish is announced with
/// the clip's name and, when it differs, where it really starts.
void main() {
  const jobId = 7;

  Map<String, dynamic> trimJob(
    String status, {
    Map<String, Object?> detail = const {},
  }) => {
    'id': jobId,
    'kind': JobKinds.videoTrim,
    'lane': 'copy',
    'name': 'Trim clip.mp4',
    'params': {
      'relPath': 'Movies/clip.mp4',
      'serial': 'USB1',
      'startMs': 0,
      'endMs': 10000,
    },
    'detail': detail,
    'status': status,
    'createdAt': '2026-10-21T10:00:00Z',
  };

  late StreamController<FileEvent> events;
  late List<int> canceled;
  late List<({String relPath, String? serial, int startMs, int endMs})> trims;
  late JobsController jobs;

  // Built inside each test, so its streams deliver in the test's fake time.
  void setUpJobs() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    events = StreamController<FileEvent>.broadcast();
    canceled = [];
    trims = [];
    jobs = JobsController(
      listJobs: ({required kinds}) async => const [],
      cancelJob: (id) async {
        canceled.add(id);
        return Job.fromJson(trimJob('canceled'));
      },
      retryJob: (id) async {},
      events: () => events.stream,
      session: () => ValueNotifier<String?>(null),
    )..start();
    addTearDown(() {
      jobs.dispose();
      events.close();
    });
  }

  Future<PlaybackPosition> noPosition() async => const PlaybackPosition();

  Future<void> settle(WidgetTester tester) async {
    // Bounded pumps: the loader and the progress bar never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    setUpJobs();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoViewerPage(
          url: Uri.http('quark.test', '/api/v0/files/download', {
            'filePath': 'Movies/clip.mp4',
            'serial': 'USB1',
          }),
          name: 'clip.mp4',
          canAutoplay: () => false,
          loadPlayback: (relPath, {serial}) => noPosition(),
          savePlayback:
              (relPath, {serial, required position, required duration}) =>
                  noPosition(),
          setPlaybackWatched: (relPath, {serial, required watched}) =>
              noPosition(),
          loadTranscodeFormats: (relPath, {serial}) async =>
              const <TranscodeFormat>[],
          transcodeVideo: (relPath, {serial, required format}) async => 0,
          trimVideo:
              (relPath, {serial, required startMs, required endMs}) async {
                trims.add((
                  relPath: relPath,
                  serial: serial,
                  startMs: startMs,
                  endMs: endMs,
                ));
                return jobId;
              },
          jobs: jobs,
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens Trim Clip from the menu and presses Save Clip.
  Future<void> saveClip(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('video_viewer_more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('video_viewer_trim')));
    await settle(tester);
    await tester.tap(find.text('Save Clip'));
    await settle(tester);
  }

  final progress = find.byKey(const ValueKey('video_viewer_trim_progress'));
  final cancel = find.byKey(const ValueKey('video_viewer_trim_cancel'));

  testWidgets('Save Clip queues the trim and shows it running with Cancel', (
    tester,
  ) async {
    await pumpPage(tester);
    await saveClip(tester);

    expect(trims, [
      (relPath: 'Movies/clip.mp4', serial: 'USB1', startMs: 0, endMs: 10000),
    ]);
    expect(find.text('Trim started'), findsOneWidget);
    expect(progress, findsOneWidget);
    expect(
      find.descendant(of: progress, matching: find.byType(QuarkLoader)),
      findsOneWidget,
      reason: 'a trim has no percentage to show, so it is drawn busy',
    );
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
    expect(find.text('Save Clip'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cancel stops the job and puts the menu back', (tester) async {
    await pumpPage(tester);
    await saveClip(tester);

    await tester.tap(cancel);
    await settle(tester);
    // "Trim started" slides away before "Trim canceled" slides in.
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    expect(canceled, [jobId]);
    expect(progress, findsNothing);
    expect(find.byKey(const ValueKey('video_viewer_more')), findsOneWidget);
    expect(find.text('Trim canceled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished trim clears the progress and is announced with '
      'where the clip starts', (tester) async {
    await pumpPage(tester);
    final said = <String>[];
    final subscription = jobs.announcements.listen((a) => said.add(a.message));
    addTearDown(subscription.cancel);
    await saveClip(tester);

    events.add(
      FileEvent(kind: 'job_started', path: '', data: trimJob('running')),
    );
    await settle(tester);
    expect(progress, findsOneWidget, reason: 'still running');

    events.add(
      FileEvent(
        kind: 'job_completed',
        path: '',
        data: trimJob(
          'completed',
          detail: {'relPath': 'Movies/clip_trimmed.mp4', 'actualStartMs': 3000},
        ),
      ),
    );
    await settle(tester);

    expect(progress, findsNothing);
    expect(said, [
      'Clip saved as clip_trimmed.mp4. It starts at 0:03 instead of 0:00, '
          'the closest point this video can be cut.',
    ]);

    await tester.pumpWidget(const SizedBox());
  });
}
