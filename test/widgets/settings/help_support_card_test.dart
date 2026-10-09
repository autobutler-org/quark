import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/app_log_sink.dart';
import 'package:quark/widgets/settings/help_support_card.dart';

class _FakeSink implements AppLogSink {
  _FakeSink(this.contents, {this.persists = true});

  final String contents;

  @override
  final bool persists;

  @override
  void write(String entry) {}

  @override
  Future<String> read() async => contents;
}

void main() {
  const copyButton = ValueKey('help_copy_app_logs');

  Future<List<String>> pumpCard(WidgetTester tester, AppLogSink sink) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpSupportCard(log: AppLog(sink: sink)),
        ),
      ),
    );
    return copied;
  }

  testWidgets('copies the app log to the clipboard', (tester) async {
    final copied = await pumpCard(tester, _FakeSink('INFO App started\n'));

    await tester.tap(find.byKey(copyButton));
    await tester.pump();

    expect(copied, ['INFO App started\n']);
    expect(find.text('App logs copied'), findsOneWidget);
  });

  testWidgets('says so when there is nothing logged yet', (tester) async {
    await pumpCard(tester, _FakeSink(''));

    await tester.tap(find.byKey(copyButton));
    await tester.pump();

    expect(find.text('No app logs yet'), findsOneWidget);
  });

  testWidgets('offers no copy where no log is kept', (tester) async {
    await pumpCard(tester, _FakeSink('', persists: false));

    expect(find.byKey(copyButton), findsNothing);
    expect(find.text('Report an issue'), findsOneWidget);
  });
}
