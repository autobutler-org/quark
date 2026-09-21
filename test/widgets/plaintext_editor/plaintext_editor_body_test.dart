import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/plaintext_editor/plaintext_editor_body.dart';

Future<void> pumpBody(WidgetTester tester, {required bool spellCheck}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaintextEditorBody(
          loading: false,
          error: null,
          onRetry: () {},
          controller: TextEditingController(text: 'Teh quick brown fox'),
          spellCheck: spellCheck,
        ),
      ),
    ),
  );
}

SpellCheckConfiguration? configOf(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).spellCheckConfiguration;

void main() {
  testWidgets('a prose file is spell checked on a platform that can', (
    tester,
  ) async {
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = true;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);

    await pumpBody(tester, spellCheck: true);

    expect(configOf(tester), isNot(const SpellCheckConfiguration.disabled()));
  });

  testWidgets('a prose file on web and desktop opens without an error', (
    tester,
  ) async {
    // The platform has no spell checker. An enabled configuration here would
    // be reported as a FlutterError, which is what the gating prevents.
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = false;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);

    await pumpBody(tester, spellCheck: true);

    expect(tester.takeException(), isNull);
    expect(configOf(tester), const SpellCheckConfiguration.disabled());
  });

  testWidgets('a code file is never spell checked', (tester) async {
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = true;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);

    await pumpBody(tester, spellCheck: false);

    expect(configOf(tester), const SpellCheckConfiguration.disabled());
  });
}
