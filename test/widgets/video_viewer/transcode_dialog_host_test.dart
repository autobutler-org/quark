import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/video_viewer/transcode_dialog_host.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  const formats = [
    TranscodeFormat(format: 'mp4', label: 'MP4'),
    TranscodeFormat(format: 'mov', label: 'MOV'),
  ];

  /// Pumps a button that opens the host, and returns a getter for what the
  /// dialog answered once it closed.
  Future<(String, TranscodeQuality)? Function()> pumpOpener(
    WidgetTester tester,
    Future<List<TranscodeFormat>> Function() loadFormats,
  ) async {
    (String, TranscodeQuality)? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await TranscodeDialogHost.show(
                context,
                loadFormats: loadFormats,
                sourceFormat: 'mov',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('loads the formats and answers with the choice', (tester) async {
    final result = await pumpOpener(tester, () async => formats);

    expect(find.byKey(const ValueKey('transcode_format_mp4')), findsOneWidget);
    // The video's own format stays in the row, disabled at original quality.
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('transcode_format_mov')),
          )
          .onSelected,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('transcode_format_mp4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transcode_convert')));
    await tester.pumpAndSettle();

    expect(result(), ('mp4', TranscodeQuality.original));
  });

  testWidgets('shows why the load failed and loads again on retry', (
    tester,
  ) async {
    var calls = 0;
    await pumpOpener(tester, () async {
      calls++;
      if (calls == 1) throw const ApiException(501);
      return formats;
    });

    expect(find.text(Errors.ffmpegMissing), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transcode_retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text(Errors.ffmpegMissing), findsNothing);
    expect(find.byKey(const ValueKey('transcode_format_mp4')), findsOneWidget);
  });

  testWidgets('answers null when canceled', (tester) async {
    final result = await pumpOpener(tester, () async => formats);

    await tester.tap(find.byKey(const ValueKey('transcode_cancel')));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });
}
