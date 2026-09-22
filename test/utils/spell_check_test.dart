import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/spell_check.dart';

void main() {
  testWidgets('spell checks where the platform has a spell checker', (
    tester,
  ) async {
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = true;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);

    expect(proseSpellCheck(), isNot(const SpellCheckConfiguration.disabled()));
  });

  testWidgets('turns spell check off where the platform has none', (
    tester,
  ) async {
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = false;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);

    expect(proseSpellCheck(), const SpellCheckConfiguration.disabled());
  });
}
