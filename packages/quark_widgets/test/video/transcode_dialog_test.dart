import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The dialog a video is converted from: a format that disables the video's
/// own, no quality to choose, a layout that never shifts under a tap, and the
/// loading, error, and cancel paths.
void main() {
  const formats = [
    TranscodeFormatOption(format: 'mp4', label: 'MP4'),
    TranscodeFormatOption(format: 'mov', label: 'MOV'),
    TranscodeFormatOption(format: 'mkv', label: 'MKV'),
  ];

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    List<String>? events,
    List<TranscodeFormatOption> formats = formats,
    bool isLoading = false,
    String? error,
  }) {
    return pumpAt(
      tester,
      TranscodeDialog(
        formats: formats,
        sourceFormat: 'MOV',
        isLoading: isLoading,
        error: error,
        onConvert: (format) => events?.add('convert:$format'),
        onCancel: () => events?.add('cancel'),
        onRetry: () => events?.add('retry'),
      ),
      size: size,
    );
  }

  Finder format(String name) => find.byKey(ValueKey('transcode_format_$name'));
  final convert = find.byKey(const ValueKey('transcode_convert'));

  bool convertEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(convert).onPressed != null;

  bool chipEnabled(WidgetTester tester, String name) =>
      tester.widget<ChoiceChip>(format(name)).onSelected != null;

  /// Every chip's rect, plus the convert button's, keyed by chip key.
  Map<Key?, Rect> layout(WidgetTester tester) => {
    for (final element in find.byType(ChoiceChip).evaluate())
      element.widget.key: tester.getRect(find.byWidget(element.widget)),
    convert.evaluate().single.widget.key: tester.getRect(convert),
  };

  testBothViewports('disables the video\'s own format and offers no quality', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    expect(tester.takeException(), isNull);
    expect(chipEnabled(tester, 'mp4'), isTrue);
    expect(chipEnabled(tester, 'mkv'), isTrue);
    expect(format('mov'), findsOneWidget);
    expect(chipEnabled(tester, 'mov'), isFalse);
    // One chip per format, and no quality chips beside them.
    expect(find.byType(ChoiceChip), findsNWidgets(formats.length));
    expect(convertEnabled(tester), isFalse);

    await tester.tap(format('mov'), warnIfMissed: false);
    await tester.pump();
    expect(convertEnabled(tester), isFalse);
  });

  testBothViewports('choosing a format moves nothing', (tester, size) async {
    const many = [
      TranscodeFormatOption(format: 'mp4', label: 'MP4'),
      TranscodeFormatOption(format: 'mov', label: 'MOV'),
      TranscodeFormatOption(format: 'mkv', label: 'MKV'),
      TranscodeFormatOption(format: 'webm', label: 'WebM'),
      TranscodeFormatOption(format: 'avi', label: 'AVI'),
      TranscodeFormatOption(format: 'wmv', label: 'WMV'),
      TranscodeFormatOption(format: 'mpeg', label: 'MPEG'),
      TranscodeFormatOption(format: '3gp', label: '3GP'),
    ];
    await pumpDialog(tester, size: size, formats: many);
    final before = layout(tester);

    for (final name in ['mp4', 'webm', '3gp']) {
      await tester.tap(format(name));
      await tester.pumpAndSettle();
      expect(layout(tester), before, reason: 'after choosing $name');
    }
  });

  testBothViewports('reports the chosen format', (tester, size) async {
    final events = <String>[];
    await pumpDialog(tester, size: size, events: events);

    await tester.tap(format('mkv'));
    await tester.pump();
    expect(convertEnabled(tester), isTrue);
    await tester.tap(convert);
    await tester.pump();

    expect(events, ['convert:mkv']);
  });

  testBothViewports('shows a spinner while the formats load', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size, formats: const [], isLoading: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(convertEnabled(tester), isFalse);
  });

  testBothViewports('shows a failed load with a retry, and the cancel', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpDialog(
      tester,
      size: size,
      events: events,
      formats: const [],
      error: "Couldn't convert the video.",
    );

    expect(find.text("Couldn't convert the video."), findsOneWidget);
    expect(convertEnabled(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('transcode_retry')));
    await tester.tap(find.byKey(const ValueKey('transcode_cancel')));
    await tester.pump();

    expect(events, ['retry', 'cancel']);
  });

  testWidgets('says so when there is nothing to convert to', (tester) async {
    await pumpDialog(
      tester,
      formats: const [TranscodeFormatOption(format: 'mov', label: 'MOV')],
    );

    expect(find.textContaining('no formats'), findsOneWidget);
  });

  testWidgets('renders on the light tokens too', (tester) async {
    await pumpAt(
      tester,
      TranscodeDialog(
        formats: formats,
        onConvert: (format) {},
        onCancel: () {},
        onRetry: () {},
      ),
      brightness: Brightness.light,
      size: narrowViewport,
    );
    expect(tester.takeException(), isNull);
  });
}
