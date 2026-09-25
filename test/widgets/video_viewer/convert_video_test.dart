import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/video_viewer/convert_video.dart';

void main() {
  final listed = <(String, String?)>[];
  setUp(listed.clear);

  Future<void> pumpAndConvert(
    WidgetTester tester,
    TranscodeVideoFn transcode,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => convertVideo(
                context,
                relPath: 'clips/trip.mov',
                serial: 'SN1',
                loadFormats: (relPath, {serial}) async {
                  listed.add((relPath, serial));
                  return const [TranscodeFormat(format: 'mp4', label: 'MP4')];
                },
                transcode: transcode,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transcode_format_mp4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transcode_convert')));
    await tester.pumpAndSettle();
  }

  testWidgets('queues the chosen conversion and says it started', (
    tester,
  ) async {
    final calls = <(String, String?, String)>[];
    await pumpAndConvert(tester, (relPath, {serial, required format}) async {
      calls.add((relPath, serial, format));
      return 1;
    });

    // The formats are the ones this video's streams fit.
    expect(listed, [('clips/trip.mov', 'SN1')]);
    expect(calls, [('clips/trip.mov', 'SN1', 'mp4')]);
    expect(find.text('Conversion started'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('shows the refusal when the job cannot be queued', (
    tester,
  ) async {
    const error = ApiException(403);
    await pumpAndConvert(
      tester,
      (relPath, {serial, required format}) async => throw error,
    );

    expect(find.text(Errors.transcode(error)), findsOneWidget);
  });
}
