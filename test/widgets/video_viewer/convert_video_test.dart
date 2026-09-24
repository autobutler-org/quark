import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/video_viewer/convert_video.dart';

void main() {
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
                loadFormats: () async => const [
                  TranscodeFormat(format: 'mp4', label: 'MP4'),
                ],
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
    final calls = <(String, String?, String, String)>[];
    await pumpAndConvert(tester, (
      relPath, {
      serial,
      required format,
      required quality,
    }) async {
      calls.add((relPath, serial, format, quality));
      return 1;
    });

    expect(calls, [('clips/trip.mov', 'SN1', 'mp4', 'original')]);
    expect(find.text('Conversion started'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('shows the refusal when the job cannot be queued', (
    tester,
  ) async {
    const error = ApiException(501);
    await pumpAndConvert(
      tester,
      (relPath, {serial, required format, required quality}) async =>
          throw error,
    );

    expect(find.text(Errors.transcode(error)), findsOneWidget);
  });
}
